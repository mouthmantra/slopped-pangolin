import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pangolin/services/tray/dbusmenu.dart';

/// A `(ia{sv}av)` layout node as GetLayout returns it.
DBusStruct node(
  int id, [
  Map<String, DBusValue> properties = const {},
  List<DBusStruct> children = const [],
]) =>
    DBusStruct([
      DBusInt32(id),
      DBusDict.stringVariant(properties),
      DBusArray.variant(children),
    ]);

DBusStruct separator(int id) =>
    node(id, {"type": const DBusString("separator")});

DBusStruct item(int id, String label, [Map<String, DBusValue> extra = const {}]) =>
    node(id, {"label": DBusString(label), ...extra});

void main() {
  group("stripMnemonics", () {
    test("removes the access key marks", () {
      expect(stripMnemonics("_File"), "File");
      expect(stripMnemonics("Save _As…"), "Save As…");
      expect(stripMnemonics("a_b_c"), "abc");
      expect(stripMnemonics("trailing_"), "trailing");
    });

    test("keeps doubled underscores as one", () {
      expect(stripMnemonics("snake__case"), "snake_case");
      expect(stripMnemonics("__init__"), "_init_");
      expect(stripMnemonics("___x"), "_x");
    });

    test("leaves other labels alone", () {
      expect(stripMnemonics("Quit"), "Quit");
      expect(stripMnemonics(""), "");
    });
  });

  group("DBusMenuNode.parse", () {
    final DBusMenuNode root = DBusMenuNode.parse(
      node(0, {"children-display": const DBusString("submenu")}, [
        separator(1),
        item(2, "_Open", {
          "icon-name": const DBusString("document-open"),
          "shortcut": DBusArray(DBusSignature("as"), [
            DBusArray.string(["Control", "o"]),
          ]),
        }),
        separator(3),
        separator(4),
        item(5, "Mute", {
          "toggle-type": const DBusString("checkmark"),
          "toggle-state": const DBusInt32(1),
        }),
        item(6, "Low", {
          "toggle-type": const DBusString("radio"),
          "toggle-state": const DBusInt32(0),
        }),
        item(7, "Unsure", {
          "toggle-type": const DBusString("checkmark"),
          "toggle-state": const DBusInt32(-1),
        }),
        item(8, "Hidden", {"visible": const DBusBoolean(false)}),
        item(9, "Disabled", {"enabled": const DBusBoolean(false)}),
        node(10, {
          "label": const DBusString("_Devices"),
          "children-display": const DBusString("submenu"),
        }, [
          item(11, "Phone"),
        ]),
        // Qt: a submenu whose entries come after AboutToShow.
        item(12, "Later", {"children-display": const DBusString("submenu")}),
        item(13, "Danger", {"disposition": const DBusString("alert")}),
        item(14, "Picture", {"icon-data": DBusArray.byte([137, 80, 78, 71])}),
        separator(15),
      ]),
    )!;

    DBusMenuNode child(int id) => root.find(id)!;

    test("reads ids, labels and children", () {
      expect(root.id, 0);
      expect(root.isSubmenu, isTrue);
      expect(root.children.map((e) => e.id), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15]);
      expect(child(2).label, "_Open");
      expect(child(2).displayLabel, "Open");
      expect(child(2).iconName, "document-open");
      expect(child(2).hasIcon, isTrue);
    });

    test("defaults: enabled, visible, standard, no toggle", () {
      final DBusMenuNode open = child(2);
      expect(open.enabled, isTrue);
      expect(open.visible, isTrue);
      expect(open.isSeparator, isFalse);
      expect(open.toggleType, DBusMenuToggleType.none);
      expect(open.disposition, DBusMenuDisposition.normal);
      expect(open.isSubmenu, isFalse);
    });

    test("separators", () {
      expect(child(1).isSeparator, isTrue);
      expect(child(2).isSeparator, isFalse);
    });

    test("checkmarks and radio items", () {
      expect(child(5).toggleType, DBusMenuToggleType.checkmark);
      expect(child(5).toggleState, isTrue);
      expect(child(6).toggleType, DBusMenuToggleType.radio);
      expect(child(6).toggleState, isFalse);
      expect(child(7).toggleState, isNull);
    });

    test("toggle-state sent as a boolean", () {
      final DBusMenuNode parsed = DBusMenuNode.parse(
        item(1, "x", {
          "toggle-type": const DBusString("checkmark"),
          "toggle-state": const DBusBoolean(true),
        }),
      )!;
      expect(parsed.toggleState, isTrue);
    });

    test("hidden and disabled entries", () {
      expect(child(8).visible, isFalse);
      expect(child(9).enabled, isFalse);
    });

    test("submenus, also before their entries arrive", () {
      expect(child(10).isSubmenu, isTrue);
      expect(child(10).displayLabel, "Devices");
      expect(child(10).children.single.label, "Phone");
      expect(child(12).isSubmenu, isTrue);
      expect(child(12).children, isEmpty);
    });

    test("disposition and icon data", () {
      expect(child(13).disposition, DBusMenuDisposition.alert);
      expect(child(14).iconData, [137, 80, 78, 71]);
      expect(identical(child(14).iconData, child(14).iconData), isTrue);
      expect(child(14).hasIcon, isTrue);
    });

    test("shown entries: no hidden ones, no separators at the ends or twice", () {
      expect(
        root.shownChildren.map((e) => e.id),
        [2, 3, 5, 6, 7, 9, 10, 12, 13, 14],
      );
    });

    test("an entry whose separators are all that is left shows nothing", () {
      final DBusMenuNode only = DBusMenuNode.parse(
        node(0, {}, [separator(1), item(2, "x", {"visible": const DBusBoolean(false)}), separator(3)]),
      )!;
      expect(only.shownChildren, isEmpty);
    });
  });

  group("malformed layouts", () {
    test("not a layout", () {
      expect(DBusMenuNode.parse(const DBusString("nope")), isNull);
      expect(DBusMenuNode.parse(DBusStruct([const DBusInt32(1)])), isNull);
      expect(
        DBusMenuNode.parse(
          DBusStruct([
            const DBusString("id"),
            DBusDict.stringVariant({}),
            DBusArray.variant([]),
          ]),
        ),
        isNull,
      );
    });

    test("bad children are skipped", () {
      final DBusMenuNode parsed = DBusMenuNode.parse(
        DBusStruct([
          const DBusInt32(0),
          DBusDict.stringVariant({}),
          DBusArray.variant([
            const DBusString("junk"),
            item(1, "ok"),
            DBusStruct([const DBusInt32(2)]),
          ]),
        ]),
      )!;
      expect(parsed.children.map((e) => e.id), [1]);
    });

    test("properties of the wrong type fall back to their defaults", () {
      final DBusMenuNode parsed = DBusMenuNode.parse(
        node(1, {
          "label": const DBusInt32(3),
          "enabled": const DBusString("yes"),
          "toggle-type": const DBusBoolean(true),
          "icon-data": const DBusString("png"),
        }),
      )!;
      expect(parsed.label, "");
      expect(parsed.enabled, isTrue);
      expect(parsed.toggleType, DBusMenuToggleType.none);
      expect(parsed.iconData, isNull);
    });

    test("deep nesting is cut", () {
      DBusStruct nested = item(100, "leaf");
      for (int i = 99; i >= 0; i--) {
        nested = node(i, {}, [nested]);
      }
      final DBusMenuNode parsed = DBusMenuNode.parse(nested)!;
      int depth = 0;
      DBusMenuNode current = parsed;
      while (current.children.isNotEmpty) {
        current = current.children.single;
        depth++;
      }
      expect(depth, DBusMenuNode.maxDepth);
    });
  });

  group("ItemsPropertiesUpdated", () {
    final DBusMenuNode root = DBusMenuNode.parse(
      node(0, {}, [
        item(1, "Mute", {
          "toggle-type": const DBusString("checkmark"),
          "toggle-state": const DBusInt32(0),
        }),
        node(2, {"label": const DBusString("More")}, [item(3, "Deep")]),
        item(4, "Other"),
      ]),
    )!;

    test("reads the signal's arguments", () {
      final updates = parseMenuPropertyUpdates([
        DBusArray(DBusSignature("(ia{sv})"), [
          DBusStruct([
            const DBusInt32(1),
            DBusDict.stringVariant({"toggle-state": const DBusInt32(1)}),
          ]),
        ]),
        DBusArray(DBusSignature("(ias)"), [
          DBusStruct([const DBusInt32(3), DBusArray.string(["label"])]),
        ]),
      ]);
      expect(updates.updated.keys, [1]);
      expect(updates.updated[1]!["toggle-state"], const DBusInt32(1));
      expect(updates.removed, {3: ["label"]});
    });

    test("applies updates and removals, sharing what didn't change", () {
      final DBusMenuNode updated = root.withProperties(
        {1: {"toggle-state": const DBusInt32(1)}},
        {3: ["label"]},
      );
      expect(updated.find(1)!.toggleState, isTrue);
      expect(updated.find(1)!.label, "Mute");
      expect(updated.find(3)!.label, "");
      expect(identical(updated.find(4), root.find(4)), isTrue);
      expect(identical(updated.find(1), root.find(1)), isFalse);
      // The original is untouched.
      expect(root.find(1)!.toggleState, isFalse);
      expect(root.find(3)!.label, "Deep");
    });

    test("updates for unknown entries change nothing", () {
      expect(
        identical(root.withProperties({42: {"label": const DBusString("x")}}, {}), root),
        isTrue,
      );
    });

    test("malformed arguments are ignored", () {
      final updates = parseMenuPropertyUpdates([
        const DBusString("junk"),
        DBusArray.string(["more junk"]),
      ]);
      expect(updates.updated, isEmpty);
      expect(updates.removed, isEmpty);
      expect(parseMenuPropertyUpdates(const []).updated, isEmpty);
    });
  });
}
