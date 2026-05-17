/// AST nodes for the DSL boolean expression language.
///
/// Grammar (left-recursive, parsed via Pratt-style precedence):
///   expr     := or
///   or       := and ('OR' and)*
///   and      := not ('AND' not)*
///   not      := 'NOT' not | cmp
///   cmp      := term op term ('AND'/'OR' implicitly belong to or/and)
///   op       := '<' | '<=' | '>' | '>=' | '==' | '!='
///   term     := number | identifier | '(' expr ')'
///   identifier := names like rsi, ema_fast, close (resolved at eval time)
sealed class Expr {
  /// Evaluate against a context: { name → value }. Returns null if any
  /// referenced identifier is null (warm-up).
  Object? eval(Map<String, double?> ctx);
}

class NumberExpr extends Expr {
  final double value;
  NumberExpr(this.value);
  @override
  Object? eval(Map<String, double?> ctx) => value;
}

class IdentExpr extends Expr {
  final String name;
  IdentExpr(this.name);
  @override
  Object? eval(Map<String, double?> ctx) => ctx[name];
}

enum CmpOp { lt, lte, gt, gte, eq, neq }
enum BoolOp { and, or }

class CompareExpr extends Expr {
  final Expr left;
  final CmpOp op;
  final Expr right;
  CompareExpr(this.left, this.op, this.right);

  @override
  Object? eval(Map<String, double?> ctx) {
    final l = left.eval(ctx);
    final r = right.eval(ctx);
    if (l == null || r == null) return null;
    final ld = (l as num).toDouble();
    final rd = (r as num).toDouble();
    switch (op) {
      case CmpOp.lt:
        return ld < rd;
      case CmpOp.lte:
        return ld <= rd;
      case CmpOp.gt:
        return ld > rd;
      case CmpOp.gte:
        return ld >= rd;
      case CmpOp.eq:
        return ld == rd;
      case CmpOp.neq:
        return ld != rd;
    }
  }
}

class BoolExpr extends Expr {
  final Expr left;
  final BoolOp op;
  final Expr right;
  BoolExpr(this.left, this.op, this.right);

  @override
  Object? eval(Map<String, double?> ctx) {
    final l = left.eval(ctx);
    final r = right.eval(ctx);
    if (l == null || r == null) return null;
    final lb = l as bool;
    final rb = r as bool;
    return op == BoolOp.and ? (lb && rb) : (lb || rb);
  }
}

class NotExpr extends Expr {
  final Expr inner;
  NotExpr(this.inner);
  @override
  Object? eval(Map<String, double?> ctx) {
    final v = inner.eval(ctx);
    if (v == null) return null;
    return !(v as bool);
  }
}

class ParseError implements Exception {
  final String message;
  final int position;
  ParseError(this.message, this.position);
  @override
  String toString() => 'ParseError at $position: $message';
}
