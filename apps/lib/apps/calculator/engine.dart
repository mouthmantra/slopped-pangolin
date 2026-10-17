/*
Copyright 2026 The dahliaOS Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:math' as math;

class CalculatorException implements Exception {
  const CalculatorException(this.message);
  final String message;

  @override
  String toString() => message;
}

enum AngleMode { degrees, radians }

/// Evaluates calculator expressions such as `2×(3+4)^2 − sin(30) + 5!`.
///
/// Grammar (lowest to highest precedence):
///   expr    := term (('+' | '-') term)*
///   term    := factor (('×' | '*' | '÷' | '/') factor | implicit factor)*
///   factor  := unary ('^' factor)?            (right associative)
///   unary   := ('-' | '+') unary | postfix
///   postfix := primary ('!' | '%')*
///   primary := number | constant | function '(' expr ')' | '(' expr ')'
class ExpressionEvaluator {
  ExpressionEvaluator({this.angleMode = AngleMode.degrees});

  AngleMode angleMode;

  late List<String> _tokens;
  int _pos = 0;

  static const Map<String, double> constants = {
    "π": math.pi,
    "pi": math.pi,
    "e": math.e,
  };

  static const Set<String> functions = {
    "sin", "cos", "tan", "asin", "acos", "atan", "ln", "log", "sqrt", "√", //
    "abs",
  };

  double evaluate(String expression) {
    _tokens = tokenize(expression);
    _pos = 0;
    if (_tokens.isEmpty) throw const CalculatorException("Empty expression");
    final double value = _expr();
    if (_pos < _tokens.length) {
      throw CalculatorException("Unexpected '${_tokens[_pos]}'");
    }
    if (value.isNaN) throw const CalculatorException("Not a number");
    if (value.isInfinite) throw const CalculatorException("Infinity");
    return value;
  }

  static List<String> tokenize(String input) {
    final List<String> tokens = [];
    int i = 0;
    while (i < input.length) {
      final String c = input[i];
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if (RegExp(r"[0-9.]").hasMatch(c)) {
        final int start = i;
        while (i < input.length && RegExp(r"[0-9.]").hasMatch(input[i])) {
          i++;
        }
        // Scientific notation produced by results, e.g. 1.5e+21.
        if (i < input.length - 1 &&
            input[i] == "e" &&
            RegExp(r"[0-9+\-]").hasMatch(input[i + 1])) {
          i++;
          if (input[i] == "+" || input[i] == "-") i++;
          while (i < input.length && RegExp("[0-9]").hasMatch(input[i])) {
            i++;
          }
        }
        tokens.add(input.substring(start, i));
        continue;
      }
      if (RegExp("[a-z]").hasMatch(c)) {
        final int start = i;
        while (i < input.length && RegExp("[a-z]").hasMatch(input[i])) {
          i++;
        }
        tokens.add(input.substring(start, i));
        continue;
      }
      tokens.add(switch (c) {
        "−" => "-",
        "×" || "*" => "×",
        "÷" || "/" => "÷",
        _ => c,
      });
      i++;
    }
    return tokens;
  }

  String? get _peek => _pos < _tokens.length ? _tokens[_pos] : null;

  String _next() {
    if (_pos >= _tokens.length) {
      throw const CalculatorException("Incomplete expression");
    }
    return _tokens[_pos++];
  }

  double _expr() {
    double value = _term();
    while (_peek == "+" || _peek == "-") {
      final String op = _next();
      final double rhs = _term();
      value = op == "+" ? value + rhs : value - rhs;
    }
    return value;
  }

  bool _startsOperand(String? token) {
    if (token == null) return false;
    return token == "(" ||
        token == "√" ||
        double.tryParse(token) != null ||
        constants.containsKey(token) ||
        functions.contains(token);
  }

  double _term() {
    double value = _factor();
    while (true) {
      final String? token = _peek;
      if (token == "×" || token == "÷") {
        _next();
        final double rhs = _factor();
        if (token == "÷" && rhs == 0) {
          throw const CalculatorException("Can't divide by zero");
        }
        value = token == "×" ? value * rhs : value / rhs;
      } else if (_startsOperand(token)) {
        // Implicit multiplication: 2π, 3(4+1), 2sin(30).
        value *= _factor();
      } else {
        return value;
      }
    }
  }

  double _factor() {
    final double base = _unary();
    if (_peek == "^") {
      _next();
      final double exponent = _factor();
      return math.pow(base, exponent).toDouble();
    }
    return base;
  }

  double _unary() {
    if (_peek == "-") {
      _next();
      return -_unary();
    }
    if (_peek == "+") {
      _next();
      return _unary();
    }
    return _postfix();
  }

  double _postfix() {
    double value = _primary();
    while (_peek == "!" || _peek == "%") {
      final String op = _next();
      value = op == "!" ? _factorial(value) : value / 100;
    }
    return value;
  }

  double _primary() {
    final String token = _next();

    final double? number = double.tryParse(token);
    if (number != null) return number;

    if (constants.containsKey(token)) return constants[token]!;

    if (functions.contains(token)) {
      final double arg;
      if (_peek == "(") {
        _next();
        arg = _expr();
        _expect(")");
      } else {
        arg = _unary();
      }
      return _apply(token, arg);
    }

    if (token == "(") {
      final double value = _expr();
      // Be forgiving about a missing closing parenthesis at the end.
      if (_peek == ")") _next();
      return value;
    }

    throw CalculatorException("Unexpected '$token'");
  }

  void _expect(String token) {
    if (_peek == token) {
      _next();
    } else if (_peek != null) {
      throw CalculatorException("Expected '$token'");
    }
  }

  double _toRadians(double v) =>
      angleMode == AngleMode.degrees ? v * math.pi / 180 : v;

  double _fromRadians(double v) =>
      angleMode == AngleMode.degrees ? v * 180 / math.pi : v;

  double _apply(String fn, double x) {
    switch (fn) {
      case "sin":
        return _clean(math.sin(_toRadians(x)));
      case "cos":
        return _clean(math.cos(_toRadians(x)));
      case "tan":
        final double c = math.cos(_toRadians(x));
        if (c.abs() < 1e-12) throw const CalculatorException("Undefined");
        return _clean(math.tan(_toRadians(x)));
      case "asin":
        return _fromRadians(math.asin(x));
      case "acos":
        return _fromRadians(math.acos(x));
      case "atan":
        return _fromRadians(math.atan(x));
      case "ln":
        if (x <= 0) throw const CalculatorException("Invalid input");
        return math.log(x);
      case "log":
        if (x <= 0) throw const CalculatorException("Invalid input");
        return math.log(x) / math.ln10;
      case "sqrt" || "√":
        if (x < 0) throw const CalculatorException("Invalid input");
        return math.sqrt(x);
      case "abs":
        return x.abs();
    }
    throw CalculatorException("Unknown function $fn");
  }

  /// Rounds away floating point noise such as sin(180°) = 1.2e-16.
  static double _clean(double v) => v.abs() < 1e-12 ? 0 : v;

  static double _factorial(double n) {
    if (n < 0 || n != n.roundToDouble()) {
      throw const CalculatorException("Invalid input");
    }
    if (n > 170) throw const CalculatorException("Infinity");
    double result = 1;
    for (int i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  /// Formats a result for display: integers without decimals, at most 12
  /// significant digits, scientific notation for very large/small values.
  static String format(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    if (value.abs() >= 1e15 || value.abs() < 1e-9) {
      return value.toStringAsExponential(8).replaceAll(RegExp(r"\.?0+e"), "e");
    }
    String s = value.toStringAsPrecision(12);
    if (s.contains(".")) {
      s = s.replaceAll(RegExp(r"0+$"), "").replaceAll(RegExp(r"\.$"), "");
    }
    return s;
  }
}
