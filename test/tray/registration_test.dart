import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pangolin/services/tray/item.dart';
import 'package:pangolin/services/tray/watcher.dart';

void main() {
  group("parseItemAddress", () {
    test("an object path belongs to the sender (libappindicator)", () {
      final ItemAddress? address = parseItemAddress(
        "/org/ayatana/NotificationItem/steam",
        sender: ":1.42",
      );
      expect(address?.service, ":1.42");
      expect(address?.path, DBusObjectPath("/org/ayatana/NotificationItem/steam"));
    });

    test("a bus name is at /StatusNotifierItem (KDE, Qt)", () {
      final ItemAddress? address =
          parseItemAddress("org.kde.StatusNotifierItem-1234-1", sender: ":1.7");
      expect(address?.service, "org.kde.StatusNotifierItem-1234-1");
      expect(address?.path, DBusObjectPath("/StatusNotifierItem"));
    });

    test("a unique name too", () {
      expect(parseItemAddress(":1.42")?.path, DBusObjectPath("/StatusNotifierItem"));
    });

    test("service and path together (the watcher's list)", () {
      final ItemAddress? address =
          parseItemAddress(":1.42/org/ayatana/NotificationItem/nm_applet");
      expect(address?.service, ":1.42");
      expect(address?.path, DBusObjectPath("/org/ayatana/NotificationItem/nm_applet"));
      expect(
        parseItemAddress("org.kde.StatusNotifierItem-9-2/StatusNotifierItem")?.service,
        "org.kde.StatusNotifierItem-9-2",
      );
    });

    test("nonsense is refused", () {
      expect(parseItemAddress("/a/path"), isNull); // whose?
      expect(parseItemAddress(""), isNull);
      expect(parseItemAddress("not a name"), isNull);
      expect(parseItemAddress("single"), isNull);
      expect(parseItemAddress("org.example/bad//path"), isNull);
      expect(parseItemAddress("org.example/trailing/"), isNull);
      expect(parseItemAddress("/bad path", sender: ":1.2"), isNull);
      expect(parseItemAddress("${"a." * 200}b"), isNull);
    });
  });

  test("status and category strings", () {
    expect(TrayItemStatus.parse("Passive"), TrayItemStatus.passive);
    expect(TrayItemStatus.parse("Active"), TrayItemStatus.active);
    expect(TrayItemStatus.parse("NeedsAttention"), TrayItemStatus.needsAttention);
    expect(TrayItemStatus.parse("bogus"), TrayItemStatus.active);
    expect(TrayItemStatus.parse(null), TrayItemStatus.active);
    expect(TrayItemCategory.parse("Hardware"), TrayItemCategory.hardware);
    expect(TrayItemCategory.parse(null), TrayItemCategory.applicationStatus);
  });

  test("tooltip markup becomes text", () {
    expect(plainText("<b>3</b> new&nbsp;messages<br/>from &lt;Ann&gt; &amp; Bo"),
        "3 new messages\nfrom <Ann> & Bo");
    expect(plainText("  plain  "), "plain");
  });
}
