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

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

final DahliaAppSpec textEditorApp = DahliaAppSpec(
  name: "text_editor",
  title: "Text Editor",
  builder: (context, args) => TextEditorPage(files: args),
);

class _Document {
  _Document({this.path, String text = ""})
      : controller = TextEditingController(text: text),
        _saved = text;

  String? path;
  final TextEditingController controller;
  final ScrollController scroll = ScrollController();
  final FocusNode focus = FocusNode();
  String _saved;

  String get name => path == null ? "Untitled" : p.basename(path!);
  bool get modified => controller.text != _saved;

  void markSaved() => _saved = controller.text;

  void dispose() {
    controller.dispose();
    scroll.dispose();
    focus.dispose();
  }
}

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({this.files = const [], super.key});

  final List<String> files;

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class _TextEditorPageState extends State<TextEditorPage> {
  final List<_Document> _docs = [];
  int _current = 0;
  bool _wrap = true;
  double _fontSize = 14;

  bool _findVisible = false;
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();

  _Document get _doc => _docs[_current];

  @override
  void initState() {
    super.initState();
    for (final String file in widget.files) {
      _openPath(file, notify: false);
    }
    if (_docs.isEmpty) _docs.add(_newDoc());
  }

  @override
  void dispose() {
    for (final _Document d in _docs) {
      d.dispose();
    }
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  _Document _newDoc({String? path, String text = ""}) {
    final _Document doc = _Document(path: path, text: text);
    doc.controller.addListener(() => setState(() {}));
    return doc;
  }

  void _openPath(String path, {bool notify = true}) {
    final int existing = _docs.indexWhere((d) => d.path == path);
    if (existing != -1) {
      setState(() => _current = existing);
      return;
    }
    String text = "";
    final File file = File(path);
    if (file.existsSync()) {
      try {
        text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
      } on FileSystemException catch (e) {
        if (notify) _toast("Couldn't open ${p.basename(path)}: ${e.message}");
        return;
      }
    }
    final _Document doc = _newDoc(path: path, text: text);
    // Replace a pristine untitled tab.
    if (_docs.length == 1 && _docs.first.path == null && !_docs.first.modified &&
        _docs.first.controller.text.isEmpty) {
      _docs.first.dispose();
      _docs[0] = doc;
      _current = 0;
    } else {
      _docs.add(doc);
      _current = _docs.length - 1;
    }
    if (notify) setState(() {});
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open() async {
    final String? path = await showFileDialog(
      context,
      initialDirectory: _doc.path != null ? p.dirname(_doc.path!) : null,
    );
    if (path != null) _openPath(path);
  }

  Future<bool> _save({bool saveAs = false}) async {
    String? path = _doc.path;
    if (path == null || saveAs) {
      path = await showFileDialog(
        context,
        mode: FileDialogMode.save,
        suggestedName: _doc.path == null ? "Untitled.txt" : p.basename(_doc.path!),
        initialDirectory: _doc.path != null
            ? p.dirname(_doc.path!)
            : p.join(SystemUtils.home, "Documents"),
      );
      if (path == null) return false;
    }
    try {
      await File(path).writeAsString(_doc.controller.text);
      setState(() {
        _doc.path = path;
        _doc.markSaved();
      });
      return true;
    } on FileSystemException catch (e) {
      _toast("Couldn't save: ${e.message}");
      return false;
    }
  }

  Future<void> _closeTab(int index) async {
    final _Document doc = _docs[index];
    if (doc.modified) {
      setState(() => _current = index);
      final String? choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text("Save changes to ${doc.name}?"),
          content: const Text("Your changes will be lost if you don't save them."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, "discard"), child: const Text("Don't Save")),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            FilledButton(onPressed: () => Navigator.pop(context, "save"), child: const Text("Save")),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == "save" && !await _save()) return;
    }
    setState(() {
      _docs.removeAt(index).dispose();
      if (_docs.isEmpty) _docs.add(_newDoc());
      _current = _current.clamp(0, _docs.length - 1);
    });
  }

  void _findNext({bool backwards = false}) {
    final String query = _find.text;
    if (query.isEmpty) return;
    final String text = _doc.controller.text.toLowerCase();
    final String needle = query.toLowerCase();
    final TextSelection sel = _doc.controller.selection;
    int index;
    if (backwards) {
      final int from = (sel.isValid ? sel.start : text.length) - 1;
      index = from < 0 ? -1 : text.lastIndexOf(needle, from);
      if (index == -1) index = text.lastIndexOf(needle);
    } else {
      final int from = sel.isValid ? sel.end : 0;
      index = text.indexOf(needle, from);
      if (index == -1) index = text.indexOf(needle);
    }
    if (index == -1) {
      _toast("No matches for \"$query\"");
      return;
    }
    _doc.controller.selection =
        TextSelection(baseOffset: index, extentOffset: index + query.length);
    _doc.focus.requestFocus();
  }

  void _replaceOne() {
    final TextSelection sel = _doc.controller.selection;
    if (sel.isValid &&
        !sel.isCollapsed &&
        sel.textInside(_doc.controller.text).toLowerCase() == _find.text.toLowerCase()) {
      _doc.controller.text =
          sel.textBefore(_doc.controller.text) + _replace.text + sel.textAfter(_doc.controller.text);
      _doc.controller.selection =
          TextSelection.collapsed(offset: sel.start + _replace.text.length);
    }
    _findNext();
  }

  void _replaceAll() {
    if (_find.text.isEmpty) return;
    final int count = RegExp(RegExp.escape(_find.text), caseSensitive: false)
        .allMatches(_doc.controller.text)
        .length;
    _doc.controller.text = _doc.controller.text.replaceAll(
      RegExp(RegExp.escape(_find.text), caseSensitive: false),
      _replace.text,
    );
    _toast("Replaced $count occurrence${count == 1 ? "" : "s"}");
  }

  (int, int) _cursorPosition() {
    final int offset = math.max(0, _doc.controller.selection.baseOffset);
    final String before = _doc.controller.text.substring(
      0,
      math.min(offset, _doc.controller.text.length),
    );
    final int line = "\n".allMatches(before).length + 1;
    final int column = offset - (before.lastIndexOf("\n") + 1) + 1;
    return (line, column);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (int line, int column) = _cursorPosition();
    final String text = _doc.controller.text;
    final int lineCount = "\n".allMatches(text).length + 1;
    final int words = RegExp(r"\S+").allMatches(text).length;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            setState(() {
              _docs.add(_newDoc());
              _current = _docs.length - 1;
            }),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _open,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () =>
            _save(saveAs: true),
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () =>
            _closeTab(_current),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => _findVisible = true),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _findVisible = false),
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
            setState(() => _fontSize = math.min(32, _fontSize + 1)),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
            setState(() => _fontSize = math.max(8, _fontSize - 1)),
      },
      child: DahliaScaffold(
        title: Text("${_doc.modified ? "• " : ""}${_doc.name} — Text Editor"),
        titlebarActions: [
          IconButton(tooltip: "New (Ctrl+N)", icon: const Icon(Icons.note_add_outlined), onPressed: () {
            setState(() {
              _docs.add(_newDoc());
              _current = _docs.length - 1;
            });
          }),
          IconButton(tooltip: "Open (Ctrl+O)", icon: const Icon(Icons.folder_open_outlined), onPressed: _open),
          IconButton(tooltip: "Save (Ctrl+S)", icon: const Icon(Icons.save_outlined), onPressed: _save),
          PopupMenuButton<String>(
            tooltip: "More",
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              switch (v) {
                case "saveas":
                  _save(saveAs: true);
                case "find":
                  setState(() => _findVisible = true);
                case "wrap":
                  setState(() => _wrap = !_wrap);
                case "bigger":
                  setState(() => _fontSize = math.min(32, _fontSize + 1));
                case "smaller":
                  setState(() => _fontSize = math.max(8, _fontSize - 1));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: "saveas", child: Text("Save As…")),
              const PopupMenuItem(value: "find", child: Text("Find and Replace")),
              CheckedPopupMenuItem(value: "wrap", checked: _wrap, child: const Text("Word Wrap")),
              const PopupMenuItem(value: "bigger", child: Text("Zoom In")),
              const PopupMenuItem(value: "smaller", child: Text("Zoom Out")),
            ],
          ),
        ],
        body: Column(
          children: [
            if (_docs.length > 1)
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _docs.length,
                  itemBuilder: (context, i) => _TabChip(
                    label: "${_docs[i].modified ? "• " : ""}${_docs[i].name}",
                    selected: i == _current,
                    onTap: () => setState(() => _current = i),
                    onClose: () => _closeTab(i),
                  ),
                ),
              ),
            if (_findVisible)
              Material(
                color: theme.colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _find,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: "Find", isDense: true),
                          onSubmitted: (_) => _findNext(),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.keyboard_arrow_up_rounded), onPressed: () => _findNext(backwards: true)),
                      IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded), onPressed: _findNext),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _replace,
                          decoration: const InputDecoration(hintText: "Replace", isDense: true),
                          onSubmitted: (_) => _replaceOne(),
                        ),
                      ),
                      TextButton(onPressed: _replaceOne, child: const Text("Replace")),
                      TextButton(onPressed: _replaceAll, child: const Text("All")),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _findVisible = false),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: _Editor(
                key: ObjectKey(_doc),
                document: _doc,
                lineCount: lineCount,
                wrap: _wrap,
                fontSize: _fontSize,
              ),
            ),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: theme.colorScheme.surface,
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _doc.path ?? "Not saved yet",
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text("Ln $line, Col $column"),
                    const SizedBox(width: 16),
                    Text("$lineCount lines · $words words"),
                    const SizedBox(width: 16),
                    const Text("UTF-8"),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.document,
    required this.lineCount,
    required this.wrap,
    required this.fontSize,
    super.key,
  });

  final _Document document;
  final int lineCount;
  final bool wrap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle style = TextStyle(
      fontFamily: ZenitFonts.monospaceOf(context),
      fontSize: fontSize,
      height: 1.4,
      color: theme.colorScheme.onSurface,
    );

    const EdgeInsets padding = EdgeInsets.fromLTRB(8, 8, 16, 8);
    // One field filling the whole editor; it scrolls itself.
    final Widget field = TextField(
      controller: document.controller,
      focusNode: document.focus,
      scrollController: document.scroll,
      autofocus: true,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: style,
      keyboardType: TextInputType.multiline,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isCollapsed: true,
        contentPadding: padding,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!wrap)
          // Line numbers follow the field's scroll position (they are only
          // exact when lines don't wrap).
          ColoredBox(
            color: theme.colorScheme.surface.withValues(alpha: 0.5),
            child: ClipRect(
              child: AnimatedBuilder(
                animation: document.scroll,
                builder: (context, child) => Transform.translate(
                  offset: Offset(
                    0,
                    document.scroll.hasClients ? -document.scroll.offset : 0,
                  ),
                  child: child,
                ),
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, padding.top, 8, padding.bottom),
                    child: Text(
                      List.generate(lineCount, (i) => "${i + 1}").join("\n"),
                      textAlign: TextAlign.right,
                      style: style.copyWith(color: theme.disabledColor),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: wrap
              ? field
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Wide enough for the longest line, scrolled sideways.
                    final int longest = document.controller.text
                        .split("\n")
                        .fold<int>(0, (m, l) => l.length > m ? l.length : m);
                    final TextPainter painter = TextPainter(
                      text: TextSpan(text: "0", style: style),
                      textDirection: TextDirection.ltr,
                    )..layout();
                    final double width = (longest + 2) * painter.width +
                        padding.horizontal;
                    painter.dispose();
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width > constraints.maxWidth ? width : constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: field,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Material(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onClose,
                  child: const Icon(Icons.close_rounded, size: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
