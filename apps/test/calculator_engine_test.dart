import 'package:dahlia_apps/apps/calculator/engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final ExpressionEvaluator calc = ExpressionEvaluator();
  String eval(String e) => ExpressionEvaluator.format(calc.evaluate(e));

  test('basic arithmetic and precedence', () {
    expect(eval('1+2×3'), '7');
    expect(eval('(1+2)×3'), '9');
    expect(eval('10÷4'), '2.5');
    expect(eval('2^3^2'), '512');
    expect(eval('−3+5'), '2');
    expect(eval('2×−3'), '-6');
    expect(eval('0.1+0.2'), '0.3');
  });

  test('postfix operators and implicit multiplication', () {
    expect(eval('5!'), '120');
    expect(eval('50%'), '0.5');
    expect(eval('200×10%'), '20');
    expect(eval('2π'), '6.28318530718');
    expect(eval('3(4+1)'), '15');
  });

  test('functions and angle modes', () {
    calc.angleMode = AngleMode.degrees;
    expect(eval('sin(30)'), '0.5');
    expect(eval('sin(180)'), '0');
    expect(eval('√(16)+log(1000)'), '7');
    calc.angleMode = AngleMode.radians;
    expect(eval('cos(π)'), '-1');
    calc.angleMode = AngleMode.degrees;
  });

  test('errors', () {
    expect(() => calc.evaluate('1÷0'), throwsA(isA<CalculatorException>()));
    expect(() => calc.evaluate('2+'), throwsA(isA<CalculatorException>()));
    expect(() => calc.evaluate('√(−1)'), throwsA(isA<CalculatorException>()));
    expect(() => calc.evaluate(''), throwsA(isA<CalculatorException>()));
  });

  test('formatting', () {
    expect(ExpressionEvaluator.format(1e20), '1e+20');
    expect(ExpressionEvaluator.format(1 / 3), '0.333333333333');
    expect(ExpressionEvaluator.format(-2.50), '-2.5');
  });
}
