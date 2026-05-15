"""Safe evaluator for DSL boolean expressions.

The expressions are pre-compiled to a restricted AST by
:mod:`backtester.bots.dsl.parser`, so this evaluator only needs to walk a
small node set against a context of indicator values. The context is a flat
``{alias: float | None}`` dict — a ``None`` value (warm-up bar where the
indicator has not produced output yet) short-circuits the whole expression
to ``False`` so the bot doesn't act on incomplete data.
"""

from __future__ import annotations

import ast
import operator
from typing import Any


_BIN_OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
}

_CMP_OPS = {
    ast.Eq: operator.eq,
    ast.NotEq: operator.ne,
    ast.Lt: operator.lt,
    ast.LtE: operator.le,
    ast.Gt: operator.gt,
    ast.GtE: operator.ge,
}


class _UnknownValue(Exception):
    """Internal: short-circuits an expression when an alias has no value yet."""


def evaluate(tree: ast.AST, context: dict[str, float | None]) -> bool:
    """Evaluate a parsed DSL expression. Missing alias values → False."""
    try:
        result = _eval(tree, context)
    except _UnknownValue:
        return False
    return bool(result)


def _eval(node: ast.AST, ctx: dict[str, float | None]) -> Any:
    if isinstance(node, ast.Expression):
        return _eval(node.body, ctx)
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.Name):
        if node.id not in ctx:
            raise _UnknownValue(node.id)
        value = ctx[node.id]
        if value is None:
            raise _UnknownValue(node.id)
        return value
    if isinstance(node, ast.UnaryOp):
        operand = _eval(node.operand, ctx)
        if isinstance(node.op, ast.Not):
            return not operand
        if isinstance(node.op, ast.USub):
            return -operand
        if isinstance(node.op, ast.UAdd):
            return +operand
        raise ValueError(f"unsupported unary op {type(node.op).__name__}")
    if isinstance(node, ast.BinOp):
        left = _eval(node.left, ctx)
        right = _eval(node.right, ctx)
        op = _BIN_OPS.get(type(node.op))
        if op is None:
            raise ValueError(f"unsupported binary op {type(node.op).__name__}")
        return op(left, right)
    if isinstance(node, ast.BoolOp):
        # short-circuit, but if ANY operand is unknown, the whole thing
        # collapses to False to be safe.
        if isinstance(node.op, ast.And):
            for v in node.values:
                if not _eval(v, ctx):
                    return False
            return True
        if isinstance(node.op, ast.Or):
            for v in node.values:
                if _eval(v, ctx):
                    return True
            return False
        raise ValueError(f"unsupported bool op {type(node.op).__name__}")
    if isinstance(node, ast.Compare):
        # Chained comparisons (a < b < c) handled the same way Python does.
        left = _eval(node.left, ctx)
        for op_node, right_node in zip(node.ops, node.comparators):
            right = _eval(right_node, ctx)
            cmp = _CMP_OPS.get(type(op_node))
            if cmp is None:
                raise ValueError(f"unsupported comparison {type(op_node).__name__}")
            if not cmp(left, right):
                return False
            left = right
        return True
    raise ValueError(f"unsupported AST node {type(node).__name__}")
