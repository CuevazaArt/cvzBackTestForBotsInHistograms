import 'expression.dart';

/// Recursive-descent parser for boolean expressions with arithmetic comparisons.
///
/// Supported tokens: identifiers (a-z 0-9 _), numbers, AND, OR, NOT, parentheses,
/// and comparison operators (<, <=, >, >=, ==, !=).
class ExpressionParser {
  final String _src;
  int _pos = 0;

  ExpressionParser(this._src);

  Expr parse() {
    final e = _parseOr();
    _skipWs();
    if (_pos < _src.length) {
      throw ParseError('Unexpected trailing input: "${_src.substring(_pos)}"', _pos);
    }
    return e;
  }

  Expr _parseOr() {
    var left = _parseAnd();
    while (_matchKeyword('OR')) {
      final right = _parseAnd();
      left = BoolExpr(left, BoolOp.or, right);
    }
    return left;
  }

  Expr _parseAnd() {
    var left = _parseNot();
    while (_matchKeyword('AND')) {
      final right = _parseNot();
      left = BoolExpr(left, BoolOp.and, right);
    }
    return left;
  }

  Expr _parseNot() {
    _skipWs();
    if (_matchKeyword('NOT')) {
      return NotExpr(_parseNot());
    }
    return _parseCompare();
  }

  Expr _parseCompare() {
    final left = _parseTerm();
    _skipWs();
    final op = _matchCmpOp();
    if (op == null) return left;
    final right = _parseTerm();
    return CompareExpr(left, op, right);
  }

  Expr _parseTerm() {
    _skipWs();
    if (_pos >= _src.length) {
      throw ParseError('Unexpected end of input', _pos);
    }
    final c = _src[_pos];
    if (c == '(') {
      _pos++;
      final e = _parseOr();
      _skipWs();
      if (_pos >= _src.length || _src[_pos] != ')') {
        throw ParseError('Expected ")"', _pos);
      }
      _pos++;
      return e;
    }
    if (_isDigit(c) || c == '-' || c == '.') {
      return NumberExpr(_parseNumber());
    }
    if (_isAlpha(c)) {
      return IdentExpr(_parseIdent());
    }
    throw ParseError('Unexpected character: "$c"', _pos);
  }

  // ─── Tokenization helpers ─────────────────────────────────────────

  void _skipWs() {
    while (_pos < _src.length && _isWs(_src[_pos])) {
      _pos++;
    }
  }

  bool _isWs(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';
  bool _isDigit(String c) {
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        c == '_';
  }

  bool _isAlphaNum(String c) => _isAlpha(c) || _isDigit(c);

  bool _matchKeyword(String kw) {
    _skipWs();
    final end = _pos + kw.length;
    if (end > _src.length) return false;
    final slice = _src.substring(_pos, end).toUpperCase();
    if (slice != kw) return false;
    // ensure next char isn't alphanumeric (word boundary)
    if (end < _src.length && _isAlphaNum(_src[end])) return false;
    _pos = end;
    return true;
  }

  CmpOp? _matchCmpOp() {
    if (_pos >= _src.length) return null;
    if (_pos + 2 <= _src.length) {
      final two = _src.substring(_pos, _pos + 2);
      switch (two) {
        case '<=':
          _pos += 2;
          return CmpOp.lte;
        case '>=':
          _pos += 2;
          return CmpOp.gte;
        case '==':
          _pos += 2;
          return CmpOp.eq;
        case '!=':
          _pos += 2;
          return CmpOp.neq;
      }
    }
    final one = _src[_pos];
    if (one == '<') {
      _pos++;
      return CmpOp.lt;
    }
    if (one == '>') {
      _pos++;
      return CmpOp.gt;
    }
    return null;
  }

  double _parseNumber() {
    final start = _pos;
    if (_src[_pos] == '-') _pos++;
    while (_pos < _src.length && _isDigit(_src[_pos])) {
      _pos++;
    }
    if (_pos < _src.length && _src[_pos] == '.') {
      _pos++;
      while (_pos < _src.length && _isDigit(_src[_pos])) {
        _pos++;
      }
    }
    final slice = _src.substring(start, _pos);
    final d = double.tryParse(slice);
    if (d == null) throw ParseError('Invalid number: "$slice"', start);
    return d;
  }

  String _parseIdent() {
    final start = _pos;
    while (_pos < _src.length && _isAlphaNum(_src[_pos])) {
      _pos++;
    }
    return _src.substring(start, _pos);
  }
}
