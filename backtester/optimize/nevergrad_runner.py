"""Nevergrad-backed optimizer (NGOpt / CMA / DE / OnePlusOne)."""

from __future__ import annotations

import logging
from typing import Any, Callable, Optional

from backtester.optimize.objective import Objective, OptimizationResult

_LOG = logging.getLogger("backtester.optimize.nevergrad")


def _build_parametrization(search_space: dict[str, dict[str, Any]]):
    """Build a nevergrad Instrumentation from our search_space spec."""
    import nevergrad as ng

    kwargs: dict[str, Any] = {}
    for name, spec in search_space.items():
        ptype = spec.get("type", "float")
        if "choices" in spec:
            kwargs[name] = ng.p.Choice(spec["choices"])
        elif ptype == "int":
            kwargs[name] = ng.p.Scalar(
                lower=spec["low"], upper=spec["high"]
            ).set_integer_casting()
        elif ptype == "float":
            scalar = ng.p.Scalar(lower=spec["low"], upper=spec["high"])
            if spec.get("log"):
                scalar = scalar.set_mutation(sigma=1.0)  # log handled via init
            kwargs[name] = scalar
        else:
            raise ValueError(f"Unsupported param type '{ptype}' for '{name}'")

    return ng.p.Instrumentation(**kwargs)


def _resolve_optimizer(name: str, parametrization, budget: int):
    """Resolve an optimizer class by name."""
    import nevergrad as ng

    name = (name or "NGOpt").strip()
    # Common aliases
    aliases = {
        "ngopt": "NGOpt",
        "cma": "CMA",
        "de": "DE",
        "oneplusone": "OnePlusOne",
        "1+1": "OnePlusOne",
        "tbpsa": "TBPSA",
        "pso": "PSO",
    }
    canonical = aliases.get(name.lower(), name)

    try:
        cls = ng.optimizers.registry[canonical]
    except KeyError as e:
        raise ValueError(
            f"Unknown Nevergrad optimizer '{name}'. "
            f"Some valid choices: NGOpt, CMA, DE, OnePlusOne, PSO, TBPSA."
        ) from e

    return cls(parametrization=parametrization, budget=budget)


def run_nevergrad(
    objective: Objective,
    budget: int = 100,
    optimizer: str = "NGOpt",
    seed: Optional[int] = None,
    on_trial: Optional[Callable[[int, OptimizationResult], None]] = None,
) -> list[OptimizationResult]:
    """Run Nevergrad optimization. Returns all trial results sorted best→worst."""
    try:
        import nevergrad as ng  # noqa: F401
    except ImportError as e:
        raise ImportError(
            "Nevergrad not installed. Run:\n"
            "  pip install -r backtester/requirements-optimize.txt"
        ) from e

    parametrization = _build_parametrization(objective.cfg.search_space)
    if seed is not None:
        parametrization.random_state.seed(seed)

    opt = _resolve_optimizer(optimizer, parametrization, budget)

    collected: list[OptimizationResult] = []

    for trial_idx in range(budget):
        candidate = opt.ask()
        # Instrumentation returns (args, kwargs) on .value
        _, kwargs = candidate.value
        result = objective.evaluate(kwargs)
        collected.append(result)
        # Nevergrad minimizes by default → negate when maximizing
        loss = -result.score if objective.direction == "max" else result.score
        opt.tell(candidate, loss)
        if on_trial is not None:
            on_trial(trial_idx, result)

    reverse = objective.direction == "max"
    collected.sort(key=lambda r: r.score, reverse=reverse)
    return collected
