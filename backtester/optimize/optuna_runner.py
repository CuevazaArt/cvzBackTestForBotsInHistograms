"""Optuna-backed optimizer (TPE / CMA-ES / Random)."""

from __future__ import annotations

import logging
from typing import Any, Callable, Optional

from backtester.optimize.objective import Objective, OptimizationResult

_LOG = logging.getLogger("backtester.optimize.optuna")


def _build_optuna_sampler(name: str):
    """Resolve sampler by name (lazy import keeps Optuna optional)."""
    import optuna

    name = (name or "tpe").lower()
    if name == "tpe":
        return optuna.samplers.TPESampler()
    if name in ("cma", "cmaes"):
        return optuna.samplers.CmaEsSampler()
    if name == "random":
        return optuna.samplers.RandomSampler()
    if name in ("nsga2", "nsgaii"):
        return optuna.samplers.NSGAIISampler()
    raise ValueError(f"Unknown Optuna sampler: {name}")


def _suggest_params(trial, search_space: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Translate our search_space dict into Optuna trial.suggest_* calls."""
    params: dict[str, Any] = {}
    for name, spec in search_space.items():
        ptype = spec.get("type", "float")
        if "choices" in spec:
            params[name] = trial.suggest_categorical(name, spec["choices"])
        elif ptype == "int":
            params[name] = trial.suggest_int(
                name, spec["low"], spec["high"], step=spec.get("step", 1)
            )
        elif ptype == "float":
            params[name] = trial.suggest_float(
                name,
                spec["low"],
                spec["high"],
                step=spec.get("step"),
                log=spec.get("log", False),
            )
        else:
            raise ValueError(f"Unsupported param type '{ptype}' for '{name}'")
    return params


def run_optuna(
    objective: Objective,
    trials: int = 100,
    sampler: str = "tpe",
    seed: Optional[int] = None,
    on_trial: Optional[Callable[[int, OptimizationResult], None]] = None,
    cache=None,
) -> list[OptimizationResult]:
    """Run Optuna optimization. Returns all trial results sorted best→worst."""
    if cache is not None:
        objective._cache = cache
    try:
        import optuna
    except ImportError as e:
        raise ImportError(
            "Optuna not installed. Run:\n"
            "  pip install -r backtester/requirements-optimize.txt"
        ) from e

    optuna.logging.set_verbosity(optuna.logging.WARNING)

    direction = "maximize" if objective.direction == "max" else "minimize"
    study = optuna.create_study(
        direction=direction,
        sampler=_build_optuna_sampler(sampler),
    )
    if seed is not None:
        # Each Optuna sampler subclass accepts ``seed`` via its constructor
        # but ``BaseSampler`` itself doesn't, so the call is dynamic.
        study.sampler = type(study.sampler)(seed=seed)  # type: ignore[call-arg]

    collected: list[OptimizationResult] = []

    def _wrapped(trial: "optuna.trial.Trial") -> float:
        params = _suggest_params(trial, objective.cfg.search_space)
        result = objective.evaluate(params)
        collected.append(result)
        if on_trial is not None:
            on_trial(trial.number, result)
        return result.score

    study.optimize(_wrapped, n_trials=trials, show_progress_bar=False)

    # Attach final cache stats to every result (same snapshot for all trials)
    final_cache_stats = (
        objective._cache.stats() if objective._cache is not None else None
    )
    if final_cache_stats is not None:
        for r in collected:
            r.cache_stats = final_cache_stats

    # Sort: best first
    reverse = objective.direction == "max"
    collected.sort(key=lambda r: r.score, reverse=reverse)
    return collected
