"""Parse a strategy DSL document (text or dict) into a :class:`StrategySpec`.

The parser does **two** things:

1. Decodes the indicator bindings, like ``ema(close, 12) as fast``, into a
   :class:`IndicatorBinding` list that downstream code maps to
   :func:`backtester.core.indicators.add_indicators` specs.
2. Compiles the entry/exit/condition expressions into a small AST using
   Python's :mod:`ast` module restricted to comparisons, boolean ops and
   numeric literals. This avoids hand-rolling a tokenizer and gets us
   precedence and grouping (`(a AND b) OR c`) for free, while still being
   strict about what is allowed at evaluation time (see
   :mod:`backtester.bots.dsl.evaluator`).

Anything outside the allowed AST node set raises :class:`DSLParseError`.
"""

from __future__ import annotations

import ast
import re
from dataclasses import dataclass, field
from typing import Any

import yaml  # type: ignore[import-untyped]


class DSLParseError(ValueError):
    """Raised when a strategy DSL document is malformed.

    Carries the offending line/column when known so the API can surface
    them to the user.
    """

    def __init__(
        self,
        message: str,
        *,
        line: int | None = None,
        column: int | None = None,
        context: str | None = None,
    ) -> None:
        self.line = line
        self.column = column
        self.context = context
        full = message
        if line is not None:
            full += f" (line {line}"
            if column is not None:
                full += f", col {column}"
            full += ")"
        if context:
            full += f": {context}"
        super().__init__(full)


# Indicators supported in the DSL today. Keep this in sync with
# ``backtester.core.indicators._REGISTRY``.
SUPPORTED_INDICATORS = {"ema", "sma", "rsi", "macd", "bb", "vwap"}

# Identifier pattern shared by indicator aliases and column references.
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


@dataclass(frozen=True)
class IndicatorBinding:
    """One ``func(column, *args) as alias`` line from the ``indicators`` block.

    Resolved to:

    * ``func`` — indicator name from :data:`SUPPORTED_INDICATORS`.
    * ``column`` — the OHLCV column to feed the indicator (typically ``close``).
    * ``args`` — extra numeric args; positional for ``rsi(close, 14)``,
      empty for ``vwap()``.
    * ``alias`` — name the rules can reference; falls back to a deterministic
      ID when omitted (``ema_close_12``).
    """

    func: str
    column: str
    args: tuple[int | float, ...]
    alias: str

    def series_key(self) -> str:
        """Internal series key produced by :func:`add_indicators`.

        Mirrors the ``f"{name}_{period}"`` / MACD / BB conventions used in
        :mod:`backtester.core.indicators`.
        """
        if self.func in {"ema", "sma", "rsi"}:
            # e.g. ema_12, rsi_14 — all expect a single integer period.
            period = int(self.args[0])
            return f"{self.func}_{period}"
        if self.func == "macd":
            fast, slow, signal = (int(a) for a in (self.args + (12, 26, 9))[:3])
            return f"macd_{fast}_{slow}_{signal}_line"
        if self.func == "bb":
            period = int(self.args[0]) if self.args else 20
            return f"bb_{period}_middle"
        if self.func == "vwap":
            return "vwap"
        raise DSLParseError(f"Unknown indicator {self.func!r}")


@dataclass
class StrategySpec:
    """Fully-parsed DSL document, ready to instantiate a :class:`DSLBot`."""

    name: str = "DSL Strategy"
    bindings: list[IndicatorBinding] = field(default_factory=list)
    entry_long: ast.AST | None = None
    exit_long: ast.AST | None = None
    stop_loss_pct: float | None = None
    take_profit_pct: float | None = None
    size_pct: float = 2.0

    def indicators_used(self) -> list[str]:
        """Aliases referenced by indicators — handy for the validate endpoint."""
        return [b.alias for b in self.bindings]


# ── Indicator line parser ───────────────────────────────────────────────


_INDICATOR_LINE = re.compile(
    r"""
    ^
    \s*
    (?P<func>[a-zA-Z][a-zA-Z0-9_]*)            # ema / rsi / macd / ...
    \s*\(\s*
    (?P<args>[^)]*)                            # close, 12, 26, 9
    \s*\)\s*
    (?:as\s+(?P<alias>[a-zA-Z_][a-zA-Z0-9_]*))?  # optional `as fast`
    \s*$
    """,
    re.VERBOSE,
)


def _parse_indicator_line(raw: str, idx: int) -> IndicatorBinding:
    """Turn a single ``ema(close, 12) as fast`` line into a binding."""
    text = raw.strip()
    if not text:
        raise DSLParseError(f"indicators[{idx}] is empty")
    m = _INDICATOR_LINE.match(text)
    if not m:
        raise DSLParseError(
            "indicator must look like 'name(column, ...args) as alias'",
            context=text,
        )
    func = m.group("func").lower()
    if func not in SUPPORTED_INDICATORS:
        raise DSLParseError(
            f"unsupported indicator {func!r}; "
            f"choose one of {sorted(SUPPORTED_INDICATORS)}",
            context=text,
        )
    args_raw = [a.strip() for a in m.group("args").split(",") if a.strip()]
    if not args_raw and func != "vwap":
        raise DSLParseError(
            f"{func}() requires at least a column argument (e.g. {func}(close, 14))",
            context=text,
        )

    column = "close"
    numeric_args: list[int | float] = []
    if args_raw:
        # First arg may be an OHLCV column name; otherwise treat all as numeric.
        first = args_raw[0]
        if _IDENT.match(first) and first.lower() in {
            "open",
            "high",
            "low",
            "close",
            "volume",
        }:
            column = first.lower()
            rest = args_raw[1:]
        else:
            rest = args_raw
        for token in rest:
            try:
                if "." in token:
                    numeric_args.append(float(token))
                else:
                    numeric_args.append(int(token))
            except ValueError as exc:
                raise DSLParseError(
                    f"could not parse numeric argument {token!r}", context=text
                ) from exc

    alias = m.group("alias")
    if alias is None:
        suffix = "_".join(str(a) for a in numeric_args) or "default"
        alias = f"{func}_{column}_{suffix}"
    if not _IDENT.match(alias):
        raise DSLParseError(f"invalid alias {alias!r}", context=text)
    return IndicatorBinding(
        func=func,
        column=column,
        args=tuple(numeric_args),
        alias=alias,
    )


# ── Expression compiler (restricted subset of Python's AST) ─────────────


_ALLOWED_NODES: set[type[ast.AST]] = {
    ast.Expression,
    ast.BoolOp,
    ast.UnaryOp,
    ast.BinOp,
    ast.Compare,
    ast.Name,
    ast.Load,
    ast.Constant,
    ast.And,
    ast.Or,
    ast.Not,
    ast.Eq,
    ast.NotEq,
    ast.Lt,
    ast.LtE,
    ast.Gt,
    ast.GtE,
    ast.Add,
    ast.Sub,
    ast.Mult,
    ast.Div,
    ast.USub,
    ast.UAdd,
}


def _compile_condition(raw: str, location: str) -> ast.AST:
    """Validate and return the AST of an entry/exit condition.

    Accepts the lowercase boolean keywords ``and``/``or``/``not`` as well as
    their uppercased forms (``AND``/``OR``/``NOT``) so the YAML reads more
    naturally — we normalize before handing the string to :func:`ast.parse`.
    """
    if not isinstance(raw, str):
        raise DSLParseError(
            f"{location} must be a string expression", context=repr(raw)
        )
    normalized = re.sub(r"\bAND\b", "and", raw)
    normalized = re.sub(r"\bOR\b", "or", normalized)
    normalized = re.sub(r"\bNOT\b", "not", normalized)
    try:
        tree = ast.parse(normalized, mode="eval")
    except SyntaxError as exc:
        raise DSLParseError(
            f"syntax error in {location}: {exc.msg}",
            line=exc.lineno,
            column=exc.offset,
            context=raw,
        ) from exc

    for node in ast.walk(tree):
        if type(node) not in _ALLOWED_NODES:
            raise DSLParseError(
                f"disallowed construct {type(node).__name__!r} in {location}",
                context=raw,
            )
        if isinstance(node, ast.Constant) and not isinstance(
            node.value, (int, float, bool)
        ):
            raise DSLParseError(
                f"only numeric/boolean literals allowed in {location}",
                context=raw,
            )
    return tree


# ── Public parse_dsl ────────────────────────────────────────────────────


def parse_dsl(source: str | dict) -> StrategySpec:
    """Parse a DSL YAML string (or already-decoded dict) into a StrategySpec.

    Raises :class:`DSLParseError` on any structural or semantic problem so
    the validate endpoint can return a precise message.
    """
    if isinstance(source, str):
        try:
            data = yaml.safe_load(source)
        except yaml.YAMLError as exc:
            mark = getattr(exc, "problem_mark", None)
            raise DSLParseError(
                "YAML syntax error",
                line=mark.line + 1 if mark else None,
                column=mark.column + 1 if mark else None,
                context=str(exc),
            ) from exc
    else:
        data = source

    if not isinstance(data, dict):
        raise DSLParseError("DSL root must be a mapping (key/value object)")

    name = str(data.get("name") or "DSL Strategy")

    raw_indicators = data.get("indicators") or []
    if not isinstance(raw_indicators, list):
        raise DSLParseError("'indicators' must be a list of strings")
    bindings = [_parse_indicator_line(r, i) for i, r in enumerate(raw_indicators)]
    # Reject duplicate aliases.
    seen: set[str] = set()
    for b in bindings:
        if b.alias in seen:
            raise DSLParseError(f"duplicate indicator alias {b.alias!r}")
        seen.add(b.alias)

    entry = data.get("entry") or {}
    exit_ = data.get("exit") or {}
    if not isinstance(entry, dict) or not isinstance(exit_, dict):
        raise DSLParseError("'entry' and 'exit' must be mappings with a 'long' key")

    entry_expr = entry.get("long")
    exit_expr = exit_.get("long")
    if entry_expr is None:
        raise DSLParseError("'entry.long' is required (a boolean expression)")
    if exit_expr is None:
        raise DSLParseError("'exit.long' is required (a boolean expression)")

    entry_ast = _compile_condition(entry_expr, "entry.long")
    exit_ast = _compile_condition(exit_expr, "exit.long")

    # Static check: every Name referenced in a rule must be a known alias.
    known = {b.alias for b in bindings}
    for label, tree in (("entry.long", entry_ast), ("exit.long", exit_ast)):
        for node in ast.walk(tree):
            if isinstance(node, ast.Name) and node.id not in known:
                raise DSLParseError(
                    f"{label} references unknown alias {node.id!r}; "
                    f"defined aliases: {sorted(known) or 'none'}"
                )

    risk = data.get("risk") or {}
    if not isinstance(risk, dict):
        raise DSLParseError("'risk' must be a mapping")
    spec = StrategySpec(
        name=name,
        bindings=bindings,
        entry_long=entry_ast,
        exit_long=exit_ast,
        stop_loss_pct=_optional_float(risk, "stop_loss_pct"),
        take_profit_pct=_optional_float(risk, "take_profit_pct"),
        size_pct=_optional_float(risk, "size_pct") or 2.0,
    )
    return spec


def _optional_float(d: dict[str, Any], key: str) -> float | None:
    """Coerce a numeric DSL field, accepting plain numbers or None."""
    if key not in d or d[key] is None:
        return None
    val = d[key]
    if not isinstance(val, (int, float)):
        raise DSLParseError(f"'risk.{key}' must be numeric, got {type(val).__name__}")
    return float(val)
