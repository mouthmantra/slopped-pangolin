// Files' model: colour tags in user.xdg.tags, the type column's names and
// dropping files onto folders, on a temporary folder.

import 'dart:io';

import 'package:dahlia_apps/apps/files/file_ops.dart';
import 'package:dahlia_apps/apps/files/file_tags.dart';
import 'package:dahlia_apps/apps/files/files_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync("files-model"));
  tearDown(() => dir.deleteSync(recursive: true));

  group("tags", () {
    test("written and read back in user.xdg.tags, other tags kept", () {
      final File file = File(p.join(dir.path, "a.txt"))..writeAsStringSync("a");
      expect(FileTags.read(file.path), isEmpty);
      if (!FileTags.write(file.path, ["Work", "Red"])) {
        markTestSkipped("no user extended attributes on ${dir.path}");
        return;
      }
      expect(FileTags.read(file.path), ["Work", "Red"]);
      expect(FileTags.colorOf(FileTags.read(file.path)), FileTags.colors["Red"]);
      final List<String> blue = FileTags.withColor(FileTags.read(file.path), "Blue");
      expect(blue, ["Blue", "Work"]);
      expect(FileTags.write(file.path, FileTags.withColor(blue, null)), isTrue);
      expect(FileTags.read(file.path), ["Work"]);
      // A tag that isn't a colour still shows, in grey.
      expect(FileTags.colorOf(["Work"]), FileTags.colors["Gray"]);
      expect(FileTags.write(file.path, const []), isTrue);
      expect(FileTags.read(file.path), isEmpty);
      // Removing tags from an untagged file is no failure.
      expect(FileTags.write(file.path, const []), isTrue);
    });
  });

  test("type names", () {
    expect(describeType("Roadmap.pdf", FileKind.document), "PDF Document");
    expect(describeType("flower.png", FileKind.image), "PNG Image");
    expect(describeType("design.fig", FileKind.other), "Figma Design");
    expect(describeType("settings.hive", FileKind.other), "HIVE File");
    expect(describeType("notes.txt", FileKind.text), "Text Document");
    expect(describeType("Archive", FileKind.folder), "Folder");
    expect(describeType("README", FileKind.text), "Text Document");
  });

  group("dropping", () {
    test("moves into the folder, leaves a drop on the own folder alone", () async {
      final Directory target = Directory(p.join(dir.path, "Archive"))..createSync();
      final File file = File(p.join(dir.path, "a.txt"))..writeAsStringSync("a");
      await dropFiles([file.path], dir.path, copy: false);
      expect(file.existsSync(), isTrue);
      await dropFiles([file.path], target.path, copy: false);
      expect(file.existsSync(), isFalse);
      expect(File(p.join(target.path, "a.txt")).readAsStringSync(), "a");
    });

    test("copies with Ctrl, also into its own folder (as a second copy)", () async {
      final Directory target = Directory(p.join(dir.path, "Archive"))..createSync();
      final File file = File(p.join(dir.path, "a.txt"))..writeAsStringSync("a");
      await dropFiles([file.path], target.path, copy: true);
      expect(file.existsSync(), isTrue);
      expect(File(p.join(target.path, "a.txt")).existsSync(), isTrue);
      await dropFiles([file.path], dir.path, copy: true);
      expect(File(p.join(dir.path, "a (2).txt")).existsSync(), isTrue);
    });

    test("never puts a folder inside itself", () async {
      final Directory folder = Directory(p.join(dir.path, "Folder"))..createSync();
      final Directory inner = Directory(p.join(folder.path, "Inner"))..createSync();
      expect(() => dropFiles([folder.path], folder.path, copy: false), throwsA(isA<FileSystemException>()));
      expect(() => dropFiles([folder.path], inner.path, copy: true), throwsA(isA<FileSystemException>()));
      expect(inner.existsSync(), isTrue);
    });
  });
}
