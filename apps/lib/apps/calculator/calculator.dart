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

import 'package:dahlia_apps/apps/calculator/engine.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/services.dart';

final DahliaAppSpec calculatorApp = DahliaAppSpec(
  name: "calculator",
  title: "Calculator",
  builder: (context, args) => const CalculatorPage(),
);

class _HistoryEntry {
  const _HistoryEntry(this.expression, this.result);
  final String expression;
  final String result;
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final ExpressionEvaluator _evaluator = ExpressionEvaluator();
  final FocusNode _focus = FocusNode();
  final List<_HistoryEntry> _history = [];

  String _expression = "";
  String _preview = "";
  String? _error;
  bool _justEvaluated = false;
  bool _scientific = false;
  bool _showHistory = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _updatePreview() {
    _error = null;
    if (_expression.isEmpty) {
      _preview = "";
      return;
    }
    try {
      _preview = ExpressionEvaluator.format(_evaluator.evaluate(_expression));
    } on CalculatorException {
      _preview = "";
    }
  }

  void _input(String text) {
    setState(() {
      const String operators = "+−×÷^%!";
      if (_justEvaluated) {
        // Continue from the previous result with an operator, otherwise
        // start a new expression.
        if (!operators.contains(text[0])) _expression = "";
        _justEvaluated = false;
      }
      _expression += text;
      _updatePreview();
    });
  }

  void _backspace() {
    setState(() {
      _justEvaluated = false;
      if (_expression.isEmpty) return;
      // Remove whole function names like "sin(" at once.
      final Match? fn = RegExp(r"(asin|acos|atan|sin|cos|tan|ln|log|√)\($")
          .firstMatch(_expression);
      _expression = fn != null
          ? _expression.substring(0, fn.start)
          : _expression.substring(0, _expression.length - 1);
      _updatePreview();
    });
  }

  void _clear() {
    setState(() {
      _expression = "";
      _preview = "";
      _error = null;
      _justEvaluated = false;
    });
  }

  void _negate() {
    setState(() {
      if (_expression.isEmpty) return;
      _expression = _expression.startsWith("−(") && _expression.endsWith(")")
          ? _expression.substring(2, _expression.length - 1)
          : "−($_expression)";
      _updatePreview();
    });
  }

  void _evaluate() {
    if (_expression.isEmpty) return;
    setState(() {
      try {
        final String result =
            ExpressionEvaluator.format(_evaluator.evaluate(_expression));
        _history.insert(0, _HistoryEntry(_expression, result));
        if (_history.length > 50) _history.removeLast();
        _expression = result.replaceAll("-", "−");
        _preview = "";
        _error = null;
        _justEvaluated = true;
      } on CalculatorException catch (e) {
        _error = e.message;
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        event.character == "=") {
      _evaluate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.delete) {
      _clear();
      return KeyEventResult.handled;
    }
    final String? char = event.character;
    if (char == null || char.isEmpty) return KeyEventResult.ignored;
    const Map<String, String> mapping = {
      "*": "×",
      "/": "÷",
      "-": "−",
      "+": "+",
      "^": "^",
      "%": "%",
      "!": "!",
      "(": "(",
      ")": ")",
      ".": ".",
      ",": ".",
      "p": "π",
      "e": "e",
    };
    if (RegExp("[0-9]").hasMatch(char)) {
      _input(char);
      return KeyEventResult.handled;
    }
    if (mapping.containsKey(char)) {
      _input(mapping[char]!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: DahliaScaffold(
        titlebarActions: [
          Tooltip(
            message: _scientific ? "Standard" : "Scientific",
            child: ZenitIconButton(
              icon: _scientific ? Icons.calculate_outlined : Icons.functions_rounded,
              onPressed: () => setState(() => _scientific = !_scientific),
            ),
          ),
          Tooltip(
            message: "History",
            child: ZenitIconButton(
              icon: Icons.history_rounded,
              onPressed: () => setState(() => _showHistory = !_showHistory),
            ),
          ),
        ],
        body: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _Display(
                    expression: _expression,
                    preview: _preview,
                    error: _error,
                    angleMode: _scientific ? _evaluator.angleMode : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: _scientific ? _scientificPad() : _standardPad(),
                    ),
                  ),
                ],
              ),
            ),
            if (_showHistory)
              Container(
                width: 240,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: theme.dividerColor)),
                ),
                child: _HistoryPanel(
                  history: _history,
                  onSelect: (entry) => setState(() {
                    _expression = entry.expression;
                    _justEvaluated = false;
                    _updatePreview();
                  }),
                  onClear: () => setState(_history.clear),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _standardPad() {
    return _Keypad(
      columns: 4,
      keys: [
        _Key("C", _clear, kind: _KeyKind.function),
        _Key("( )", _parenthesis, kind: _KeyKind.function),
        _Key("%", () => _input("%"), kind: _KeyKind.function),
        _Key("÷", () => _input("÷"), kind: _KeyKind.operator),
        for (final String d in ["7", "8", "9"]) _Key(d, () => _input(d)),
        _Key("×", () => _input("×"), kind: _KeyKind.operator),
        for (final String d in ["4", "5", "6"]) _Key(d, () => _input(d)),
        _Key("−", () => _input("−"), kind: _KeyKind.operator),
        for (final String d in ["1", "2", "3"]) _Key(d, () => _input(d)),
        _Key("+", () => _input("+"), kind: _KeyKind.operator),
        _Key("±", _negate),
        _Key("0", () => _input("0")),
        _Key(".", () => _input(".")),
        _Key("=", _evaluate, kind: _KeyKind.equals),
      ],
      onBackspace: _backspace,
    );
  }

  void _parenthesis() {
    final int open = "(".allMatches(_expression).length;
    final int close = ")".allMatches(_expression).length;
    final bool canClose = open > close &&
        _expression.isNotEmpty &&
        !"(+−×÷^".contains(_expression[_expression.length - 1]);
    _input(canClose ? ")" : "(");
  }

  Widget _scientificPad() {
    final bool degrees = _evaluator.angleMode == AngleMode.degrees;
    return _Keypad(
      columns: 5,
      keys: [
        _Key(degrees ? "DEG" : "RAD", () {
          setState(() {
            _evaluator.angleMode = degrees ? AngleMode.radians : AngleMode.degrees;
            _updatePreview();
          });
        }, kind: _KeyKind.function),
        _Key("C", _clear, kind: _KeyKind.function),
        _Key("( )", _parenthesis, kind: _KeyKind.function),
        _Key("%", () => _input("%"), kind: _KeyKind.function),
        _Key("÷", () => _input("÷"), kind: _KeyKind.operator),
        _Key("sin", () => _input("sin("), kind: _KeyKind.function),
        for (final String d in ["7", "8", "9"]) _Key(d, () => _input(d)),
        _Key("×", () => _input("×"), kind: _KeyKind.operator),
        _Key("cos", () => _input("cos("), kind: _KeyKind.function),
        for (final String d in ["4", "5", "6"]) _Key(d, () => _input(d)),
        _Key("−", () => _input("−"), kind: _KeyKind.operator),
        _Key("tan", () => _input("tan("), kind: _KeyKind.function),
        for (final String d in ["1", "2", "3"]) _Key(d, () => _input(d)),
        _Key("+", () => _input("+"), kind: _KeyKind.operator),
        _Key("ln", () => _input("ln("), kind: _KeyKind.function),
        _Key("±", _negate),
        _Key("0", () => _input("0")),
        _Key(".", () => _input(".")),
        _Key("=", _evaluate, kind: _KeyKind.equals),
        _Key("log", () => _input("log("), kind: _KeyKind.function),
        _Key("√", () => _input("√("), kind: _KeyKind.function),
        _Key("xʸ", () => _input("^"), kind: _KeyKind.function),
        _Key("x!", () => _input("!"), kind: _KeyKind.function),
        _Key("π", () => _input("π"), kind: _KeyKind.function),
      ],
      onBackspace: _backspace,
    );
  }
}

class _Display extends StatelessWidget {
  const _Display({
    required this.expression,
    required this.preview,
    required this.error,
    required this.angleMode,
  });

  final String expression;
  final String preview;
  final String? error;
  final AngleMode? angleMode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Container(
      height: 150,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (angleMode != null)
            Align(
              alignment: Alignment.topLeft,
              child: Text(
                angleMode == AngleMode.degrees ? "DEG" : "RAD",
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              expression.isEmpty ? "0" : expression,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 24,
            child: Text(
              error ?? (preview.isEmpty ? "" : "= $preview"),
              style: theme.textTheme.titleMedium?.copyWith(
                color: error != null ? theme.colorScheme.error : muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _KeyKind { digit, operator, function, equals }

class _Key {
  const _Key(this.label, this.onPressed, {this.kind = _KeyKind.digit});
  final String label;
  final VoidCallback onPressed;
  final _KeyKind kind;
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.columns,
    required this.keys,
    required this.onBackspace,
  });

  final int columns;
  final List<_Key> keys;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final int rows = (keys.length / columns).ceil();
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: "Backspace",
            icon: const Icon(Icons.backspace_outlined),
            onPressed: onBackspace,
          ),
        ),
        for (int r = 0; r < rows; r++)
          Expanded(
            child: Row(
              children: [
                for (int c = 0; c < columns; c++)
                  Expanded(
                    child: r * columns + c < keys.length
                        ? _KeyButton(keys[r * columns + c])
                        : const SizedBox(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton(this.keyData);

  final _Key keyData;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final (Color background, Color foreground) = switch (keyData.kind) {
      _KeyKind.digit => (scheme.surface, scheme.onSurface),
      _KeyKind.function => (
          scheme.surface.withValues(alpha: 0.6),
          scheme.primary,
        ),
      _KeyKind.operator => (scheme.primary.withValues(alpha: 0.15), scheme.primary),
      _KeyKind.equals => (scheme.primary, scheme.onPrimary),
    };

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: keyData.onPressed,
          child: Center(
            child: Text(
              keyData.label,
              style: TextStyle(
                fontSize: keyData.label.length > 2 ? 15 : 22,
                fontWeight:
                    keyData.kind == _KeyKind.digit ? FontWeight.w400 : FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({
    required this.history,
    required this.onSelect,
    required this.onClear,
  });

  final List<_HistoryEntry> history;
  final ValueChanged<_HistoryEntry> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text("History", style: theme.textTheme.titleSmall),
              const Spacer(),
              if (history.isNotEmpty)
                TextButton(onPressed: onClear, child: const Text("Clear")),
            ],
          ),
        ),
        Expanded(
          child: history.isEmpty
              ? const EmptyState(
                  icon: Icons.history_rounded,
                  title: "No history yet",
                )
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final _HistoryEntry entry = history[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        entry.expression,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                      ),
                      subtitle: Text(
                        "= ${entry.result}",
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleMedium,
                      ),
                      onTap: () => onSelect(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
