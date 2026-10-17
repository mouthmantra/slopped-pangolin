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

// Generates Dart proxies from Wayland protocol XML, like wayland-scanner does
// for C. Run from the package root:
//
//   dart run tool/generate.dart
//
// Every protocols/*.xml file produces lib/src/protocols/<protocol>.dart.

import 'dart:io';

import 'package:xml/xml.dart';

const Set<String> _reserved = {
  // Reserved words and built-in identifiers. Contextual keywords such as
  // `sync`, `show` or `hide` are valid member names and are left alone.
  'abstract', 'as', 'assert', 'break', 'case', 'catch', 'class', 'const', //
  'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic', 'else',
  'enum', 'export', 'extends', 'extension', 'external', 'factory', 'false',
  'final', 'finally', 'for', 'Function', 'get', 'if', 'implements', 'import',
  'in', 'interface', 'is', 'late', 'library', 'mixin', 'new', 'null',
  'operator', 'part', 'required', 'rethrow', 'return', 'set', 'static',
  'super', 'switch', 'this', 'throw', 'true', 'try', 'typedef', 'var', 'void',
  'while', 'with',
  // Members of Proxy that generated code must not shadow.
  'id', 'version', 'connection', 'send', 'destroyed', 'userData',
};

String _pascal(String snake) => snake
    .split('_')
    .where((p) => p.isNotEmpty)
    .map((p) => p[0].toUpperCase() + p.substring(1))
    .join();

String _camel(String snake) {
  final String pascal = _pascal(snake);
  return pascal[0].toLowerCase() + pascal.substring(1);
}

String _ident(String snake) {
  String name = _camel(snake);
  if (RegExp('^[0-9]').hasMatch(name)) name = 'v$name';
  if (_reserved.contains(name)) name = '${name}_';
  return name;
}

String _doc(String? text, String indent) {
  if (text == null || text.trim().isEmpty) return '';
  final String cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return '$indent/// $cleaned\n';
}

class Arg {
  Arg(XmlElement e)
      : name = e.getAttribute('name')!,
        type = e.getAttribute('type')!,
        interface = e.getAttribute('interface'),
        nullable = e.getAttribute('allow-null') == 'true',
        summary = e.getAttribute('summary');

  final String name;
  final String type;
  final String? interface;
  final bool nullable;
  final String? summary;
}

class Message {
  Message(XmlElement e)
      : name = e.getAttribute('name')!,
        since = int.tryParse(e.getAttribute('since') ?? '') ?? 1,
        destructor = e.getAttribute('type') == 'destructor',
        summary = e.getElement('description')?.getAttribute('summary'),
        args = e.findElements('arg').map(Arg.new).toList();

  final String name;
  final int since;
  final bool destructor;
  final String? summary;
  final List<Arg> args;
}

class EnumEntry {
  EnumEntry(XmlElement e)
      : name = e.getAttribute('name')!,
        value = e.getAttribute('value')!,
        summary = e.getAttribute('summary');

  final String name;
  final String value;
  final String? summary;
}

class EnumDef {
  EnumDef(XmlElement e)
      : name = e.getAttribute('name')!,
        bitfield = e.getAttribute('bitfield') == 'true',
        entries = e.findElements('entry').map(EnumEntry.new).toList();

  final String name;
  final bool bitfield;
  final List<EnumEntry> entries;
}

class Interface {
  Interface(XmlElement e)
      : name = e.getAttribute('name')!,
        version = int.parse(e.getAttribute('version')!),
        summary = e.getElement('description')?.getAttribute('summary'),
        requests = e.findElements('request').map(Message.new).toList(),
        events = e.findElements('event').map(Message.new).toList(),
        enums = e.findElements('enum').map(EnumDef.new).toList();

  final String name;
  final int version;
  final String? summary;
  final List<Message> requests;
  final List<Message> events;
  final List<EnumDef> enums;

  String get className => _pascal(name);
}

class Protocol {
  Protocol(this.file, XmlDocument doc)
      : name = doc.rootElement.getAttribute('name')!,
        interfaces = doc.rootElement
            .findElements('interface')
            .map(Interface.new)
            .toList();

  final String file;
  final String name;
  final List<Interface> interfaces;
}

/// Maps an interface name to the protocol that defines it.
final Map<String, Protocol> _owners = {};

String _classFor(String? interface) =>
    interface != null && _owners.containsKey(interface)
        ? _pascal(interface)
        : 'Proxy';

/// Untyped object arguments (such as `wl_display.error.object_id`) may refer
/// to any object, including ones this client does not know about.
bool _isNullable(Arg arg) =>
    (arg.nullable && (arg.type == 'string' || arg.type == 'object')) ||
    (arg.type == 'object' && arg.interface == null);

String _dartType(Arg arg, {required bool forEvent}) {
  final String base = switch (arg.type) {
    'int' || 'uint' => 'int',
    'fixed' => 'double',
    'string' => 'String',
    'object' => _classFor(arg.interface),
    'new_id' => _classFor(arg.interface),
    'array' => forEvent ? 'Uint8List' : 'List<int>',
    'fd' => 'RandomAccessFile',
    _ => throw ArgumentError('unknown arg type ${arg.type}'),
  };
  return _isNullable(arg) ? '$base?' : base;
}

String _writeArg(Arg arg, String expr) => switch (arg.type) {
      'int' => 'w.int32($expr);',
      'uint' => 'w.uint32($expr);',
      'fixed' => 'w.fixed($expr);',
      'string' => 'w.string($expr);',
      'object' => _isNullable(arg) ? 'w.uint32($expr?.id ?? 0);' : 'w.uint32($expr.id);',
      'array' => 'w.array($expr);',
      'fd' => 'w.fd($expr);',
      _ => throw ArgumentError(arg.type),
    };

void _generateRequest(StringBuffer out, Interface iface, Message m, int opcode) {
  final List<Arg> newIds = m.args.where((a) => a.type == 'new_id').toList();
  if (newIds.length > 1) {
    throw UnsupportedError('${iface.name}.${m.name}: multiple new_id args');
  }
  final Arg? newId = newIds.isEmpty ? null : newIds.first;
  final bool generic = newId != null && newId.interface == null;

  final List<String> params = [];
  for (final Arg a in m.args) {
    if (a.type == 'new_id') {
      if (generic) {
        params.add('WaylandInterface<T> interface_');
        params.add('int version_');
      }
      continue;
    }
    params.add('${_dartType(a, forEvent: false)} ${_ident(a.name)}');
  }

  final String returnType = newId == null
      ? 'void'
      : generic
          ? 'T'
          : _classFor(newId.interface);
  final String typeParams = generic ? '<T extends Proxy>' : '';

  out.write(_doc(m.summary, '  '));
  if (m.since > 1) out.writeln('  ///\n  /// Available since version ${m.since}.');
  out.writeln('  $returnType ${_ident(m.name)}$typeParams(${params.join(', ')}) {');
  out.writeln('    final WireWriter w = WireWriter(id, $opcode);');

  if (newId != null) {
    if (generic) {
      out.writeln(
        '    final T created = connection.createProxy(interface_.factory, version_);',
      );
    } else {
      final String cls = _classFor(newId.interface);
      out.writeln(
        '    final $cls created = connection.createProxy($cls.new, version);',
      );
    }
  }

  for (final Arg a in m.args) {
    if (a.type == 'new_id') {
      if (generic) {
        out.writeln('    w.string(interface_.name);');
        out.writeln('    w.uint32(version_);');
      }
      out.writeln('    w.uint32(created.id);');
    } else {
      out.writeln('    ${_writeArg(a, _ident(a.name))}');
    }
  }

  out.writeln('    send(w);');
  if (m.destructor) out.writeln('    markDestroyed();');
  if (newId != null) out.writeln('    return created;');
  out.writeln('  }\n');
}

String _readArg(Arg arg) => switch (arg.type) {
      'int' => 'r.int32()',
      'uint' => 'r.uint32()',
      'fixed' => 'r.fixed()',
      'string' => arg.nullable ? 'r.string()' : "r.string() ?? ''",
      'object' => 'connection.lookup(r.uint32()) as ${_classFor(arg.interface)}?',
      'new_id' =>
        'connection.adoptServerObject(${_classFor(arg.interface)}.new, r.uint32(), version)',
      'array' => 'r.array()',
      'fd' => 'r.fd()',
      _ => throw ArgumentError(arg.type),
    };

void _generateEvents(StringBuffer out, Interface iface) {
  for (final Message m in iface.events) {
    final String types =
        m.args.map((a) => '${_dartType(a, forEvent: true)} ${_ident(a.name)}').join(', ');
    out.write(_doc(m.summary, '  '));
    out.writeln('  void Function($types)? on${_pascal(m.name)};\n');
  }

  out.writeln('  @override');
  out.writeln('  void dispatchEvent(int opcode, WireReader r) {');
  if (iface.events.isEmpty) {
    out.writeln('  }');
    return;
  }
  out.writeln('    switch (opcode) {');
  for (int i = 0; i < iface.events.length; i++) {
    final Message m = iface.events[i];
    out.writeln('      case $i:');
    final List<String> names = [];
    for (final Arg a in m.args) {
      final String local = '_${_camel(a.name)}';
      names.add(local);
      out.writeln('        final $local = ${_readArg(a)};');
    }
    out.writeln('        if (destroyed) return;');
    for (final Arg a in m.args) {
      if (a.type == 'object' && !_isNullable(a)) {
        // The referenced object is unknown (already destroyed); drop the event.
        out.writeln('        if (_${_camel(a.name)} == null) return;');
      }
    }
    final List<String> callArgs = [
      for (final Arg a in m.args)
        if (a.type == 'object' && !_isNullable(a))
          '_${_camel(a.name)}!'
        else
          '_${_camel(a.name)}',
    ];
    out.writeln('        on${_pascal(m.name)}?.call(${callArgs.join(', ')});');
    if (m.destructor) {
      // The server destroyed the object by sending this event.
      out.writeln('        markDestroyed();');
    }
  }
  out.writeln('    }');
  out.writeln('  }');
}

void _generateEnum(StringBuffer out, Interface iface, EnumDef e) {
  out.writeln('/// `${iface.name}.${e.name}`${e.bitfield ? ' (bitfield)' : ''}');
  out.writeln('abstract final class ${iface.className}${_pascal(e.name)} {');
  for (final EnumEntry entry in e.entries) {
    out.write(_doc(entry.summary, '  '));
    out.writeln('  static const int ${_ident(entry.name)} = ${entry.value};');
  }
  out.writeln('}\n');
}

String _generateProtocol(Protocol p) {
  final StringBuffer out = StringBuffer();
  out.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.');
  out.writeln('// Generated by tool/generate.dart from protocols/${p.file}.');
  out.writeln('//');
  out.writeln('// ignore_for_file: unused_import, unnecessary_cast, '
      'non_constant_identifier_names, prefer_final_locals, '
      'no_leading_underscores_for_local_identifiers, '
      'unnecessary_null_comparison, lines_longer_than_80_chars');
  out.writeln();
  out.writeln("import 'dart:io';");
  out.writeln("import 'dart:typed_data';");
  out.writeln();
  out.writeln("import 'package:wayland/src/connection.dart';");
  out.writeln("import 'package:wayland/src/proxy.dart';");
  out.writeln("import 'package:wayland/src/wire.dart';");

  final Set<String> deps = {};
  for (final Interface iface in p.interfaces) {
    for (final Message m in [...iface.requests, ...iface.events]) {
      for (final Arg a in m.args) {
        final Protocol? owner = a.interface == null ? null : _owners[a.interface];
        if (owner != null && owner != p) deps.add(owner.name);
      }
    }
  }
  for (final String dep in deps.toList()..sort()) {
    out.writeln("import 'package:wayland/src/protocols/$dep.dart';");
  }
  out.writeln();

  for (final Interface iface in p.interfaces) {
    final String cls = iface.className;
    out.write(_doc(iface.summary, ''));
    out.writeln('class $cls extends Proxy {');
    out.writeln('  $cls(super.connection, super.id, super.version);\n');
    out.writeln('  static const WaylandInterface<$cls> interface =');
    out.writeln("      WaylandInterface('${iface.name}', ${iface.version}, $cls.new);\n");
    out.writeln('  @override');
    out.writeln("  String get interfaceName => '${iface.name}';\n");
    for (int i = 0; i < iface.requests.length; i++) {
      _generateRequest(out, iface, iface.requests[i], i);
    }
    _generateEvents(out, iface);
    out.writeln('}\n');

    for (final EnumDef e in iface.enums) {
      _generateEnum(out, iface, e);
    }
  }

  return out.toString();
}

void main() {
  final List<File> files = Directory('protocols')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.xml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final List<Protocol> protocols = [
    for (final File f in files)
      Protocol(f.uri.pathSegments.last, XmlDocument.parse(f.readAsStringSync())),
  ];

  for (final Protocol p in protocols) {
    for (final Interface i in p.interfaces) {
      _owners[i.name] = p;
    }
  }

  final Directory outDir = Directory('lib/src/protocols')..createSync(recursive: true);
  final StringBuffer barrel = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln();

  for (final Protocol p in protocols) {
    File('${outDir.path}/${p.name}.dart').writeAsStringSync(_generateProtocol(p));
    barrel.writeln("export 'package:wayland/src/protocols/${p.name}.dart';");
    stdout.writeln('generated ${p.name} (${p.interfaces.length} interfaces)');
  }

  File('lib/protocols.dart').writeAsStringSync(barrel.toString());
}
