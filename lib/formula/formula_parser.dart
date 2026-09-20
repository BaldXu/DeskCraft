/// 公式表达式词法 + 语法分析（M6 公式引擎核心子集）。
///
/// 语法（递归下降）：
/// ```
/// expr    := sum ( cmpOp sum )?
/// sum     := term ( ('+' | '-') term )*
/// term    := unary ( ('*' | '/' | '%') unary )*
/// unary   := '-' unary | atom
/// atom    := NUMBER | STRING | IDENT | IDENT '(' args? ')' | '(' expr ')'
/// ```
///
/// 值类型三种种：num / String / bool。比较运算产生 bool，
/// `if(cond, a, b)` 用真值规则（非零数字、非空且非 "false" 字符串、true）。
library;

/// 词法 / 语法错误。
class FormulaSyntaxException implements Exception {
  FormulaSyntaxException(this.message);

  final String message;

  @override
  String toString() => '公式语法错误：$message';
}

// ---------------------------------------------------------------------------
// Token
// ---------------------------------------------------------------------------

enum _TokenType { number, string, ident, plus, minus, star, slash, percent, lp, rp, comma, lt, gt, le, ge, eq, ne, eof }

class _Token {
  _Token(this.type, this.value, this.pos);

  final _TokenType type;
  final Object value;
  final int pos;
}

class _Lexer {
  _Lexer(this.source);

  final String source;
  int _pos = 0;

  _Token next() {
    _skipSpaces();
    if (_pos >= source.length) return _Token(_TokenType.eof, '', _pos);
    final start = _pos;
    final ch = source[_pos];

    // 数字（支持小数）
    if (_isDigit(ch) || (ch == '.' && _pos + 1 < source.length && _isDigit(source[_pos + 1]))) {
      while (_pos < source.length && (_isDigit(source[_pos]) || source[_pos] == '.')) {
        _pos++;
      }
      final text = source.substring(start, _pos);
      final value = num.tryParse(text);
      if (value == null) throw FormulaSyntaxException('非法数字 "$text"');
      return _Token(_TokenType.number, value, start);
    }

    // 字符串（单引号或双引号）
    if (ch == "'" || ch == '"') {
      final quote = ch;
      _pos++;
      final buf = StringBuffer();
      while (_pos < source.length && source[_pos] != quote) {
        if (source[_pos] == r'\' && _pos + 1 < source.length) {
          _pos++; // 转义：\' \" \\
        }
        buf.write(source[_pos]);
        _pos++;
      }
      if (_pos >= source.length) throw FormulaSyntaxException('字符串缺少收尾引号');
      _pos++; // 吃掉收尾引号
      return _Token(_TokenType.string, buf.toString(), start);
    }

    // 标识符 / 函数名
    if (_isIdentStart(ch)) {
      while (_pos < source.length && _isIdentPart(source[_pos])) {
        _pos++;
      }
      return _Token(_TokenType.ident, source.substring(start, _pos), start);
    }

    // 符号
    _pos++;
    switch (ch) {
      case '+':
        return _Token(_TokenType.plus, ch, start);
      case '-':
        return _Token(_TokenType.minus, ch, start);
      case '*':
        return _Token(_TokenType.star, ch, start);
      case '/':
        return _Token(_TokenType.slash, ch, start);
      case '%':
        return _Token(_TokenType.percent, ch, start);
      case '(':
        return _Token(_TokenType.lp, ch, start);
      case ')':
        return _Token(_TokenType.rp, ch, start);
      case ',':
        return _Token(_TokenType.comma, ch, start);
      case '<':
        if (_peek() == '=') {
          _pos++;
          return _Token(_TokenType.le, '<=', start);
        }
        return _Token(_TokenType.lt, ch, start);
      case '>':
        if (_peek() == '=') {
          _pos++;
          return _Token(_TokenType.ge, '>=', start);
        }
        return _Token(_TokenType.gt, ch, start);
      case '=':
        if (_peek() == '=') {
          _pos++;
          return _Token(_TokenType.eq, '==', start);
        }
        throw FormulaSyntaxException('单个 = 不支持，相等比较请用 ==');
      case '!':
        if (_peek() == '=') {
          _pos++;
          return _Token(_TokenType.ne, '!=', start);
        }
        throw FormulaSyntaxException('无法识别的符号 "!"');
      default:
        throw FormulaSyntaxException('无法识别的符号 "$ch"');
    }
  }

  void _skipSpaces() {
    while (_pos < source.length && source[_pos] == ' ') {
      _pos++;
    }
  }

  String _peek() => _pos < source.length ? source[_pos] : '';

  bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  bool _isIdentStart(String c) =>
      c == '_' ||
      (c.codeUnitAt(0) >= 0x61 && c.codeUnitAt(0) <= 0x7A) ||
      (c.codeUnitAt(0) >= 0x41 && c.codeUnitAt(0) <= 0x5A);

  bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

sealed class Expr {}

class NumLiteral extends Expr {
  NumLiteral(this.value);
  final num value;
}

class StringLiteral extends Expr {
  StringLiteral(this.value);
  final String value;
}

class VariableExpr extends Expr {
  VariableExpr(this.name);
  final String name;
}

class CallExpr extends Expr {
  CallExpr(this.name, this.args);
  final String name;
  final List<Expr> args;
}

class UnaryExpr extends Expr {
  UnaryExpr(this.op, this.operand);
  final String op;
  final Expr operand;
}

class BinaryExpr extends Expr {
  BinaryExpr(this.op, this.left, this.right);
  final String op; // + - * / % < > <= >= == !=
  final Expr left;
  final Expr right;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class FormulaParser {
  FormulaParser(String source) : _lexer = _Lexer(source) {
    _current = _lexer.next();
  }

  final _Lexer _lexer;
  late _Token _current;

  /// 解析整个表达式（必须完整消费输入）。
  Expr parse() {
    final expr = _expr();
    if (_current.type != _TokenType.eof) {
      throw FormulaSyntaxException('表达式末尾有多余内容 "${_current.value}"');
    }
    return expr;
  }

  Expr _expr() {
    var left = _sum();
    const cmpOps = {_TokenType.lt, _TokenType.gt, _TokenType.le, _TokenType.ge, _TokenType.eq, _TokenType.ne};
    if (cmpOps.contains(_current.type)) {
      final op = _current.value as String;
      _advance();
      final right = _sum();
      left = BinaryExpr(op, left, right);
    }
    return left;
  }

  Expr _sum() {
    var left = _term();
    while (_current.type == _TokenType.plus || _current.type == _TokenType.minus) {
      final op = _current.value as String;
      _advance();
      left = BinaryExpr(op, left, _term());
    }
    return left;
  }

  Expr _term() {
    var left = _unary();
    while (_current.type == _TokenType.star || _current.type == _TokenType.slash || _current.type == _TokenType.percent) {
      final op = _current.value as String;
      _advance();
      left = BinaryExpr(op, left, _unary());
    }
    return left;
  }

  Expr _unary() {
    if (_current.type == _TokenType.minus) {
      _advance();
      return UnaryExpr('-', _unary());
    }
    return _atom();
  }

  Expr _atom() {
    final token = _current;
    switch (token.type) {
      case _TokenType.number:
        _advance();
        return NumLiteral(token.value as num);
      case _TokenType.string:
        _advance();
        return StringLiteral(token.value as String);
      case _TokenType.ident:
        _advance();
        if (_current.type == _TokenType.lp) {
          _advance();
          final args = <Expr>[];
          if (_current.type != _TokenType.rp) {
            args.add(_expr());
            while (_current.type == _TokenType.comma) {
              _advance();
              args.add(_expr());
            }
          }
          if (_current.type != _TokenType.rp) throw FormulaSyntaxException('函数 ${token.value} 缺少 ")"');
          _advance();
          return CallExpr(token.value as String, args);
        }
        return VariableExpr(token.value as String);
      case _TokenType.lp:
        _advance();
        final expr = _expr();
        if (_current.type != _TokenType.rp) throw FormulaSyntaxException('缺少 ")"');
        _advance();
        return expr;
      case _TokenType.eof:
        throw FormulaSyntaxException('表达式意外结束');
      default:
        throw FormulaSyntaxException('意外的符号 "${token.value}"');
    }
  }

  void _advance() => _current = _lexer.next();
}

/// 便利入口：解析一段表达式源码。
Expr parseFormula(String source) => FormulaParser(source).parse();
