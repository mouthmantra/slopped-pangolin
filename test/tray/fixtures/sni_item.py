#!/usr/bin/env python3
"""A StatusNotifierItem with a dbusmenu, for testing Pangolin's tray.

Registers like libappindicator (an object path) or like KDE and Qt (a bus
name), logs every call it gets on stdout and takes commands on stdin, one per
line:

  status Passive|Active|NeedsAttention   title TEXT    icon NAME
  pixmap SIZE    attention NAME    overlay NAME    tooltip TITLE|DESCRIPTION
  addmenu LABEL  quit

Needs python3-dbus-next. Run it on a private bus only.
"""

import argparse
import asyncio
import os
import sys

from dbus_next import BusType, Message, MessageType, Variant
from dbus_next.aio import MessageBus
from dbus_next.errors import DBusError
from dbus_next.service import PropertyAccess, ServiceInterface, dbus_property, method, signal

WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"


def log(*parts):
    print(*parts, flush=True)


def square(size, argb):
    return [size, size, bytes(argb) * (size * size)]


class Item(ServiceInterface):
    def __init__(self, args):
        super().__init__("org.kde.StatusNotifierItem")
        self.args = args
        self.status = args.status
        self.title = args.title
        self.icon_name = args.icon
        self.pixmaps = [square(16, [255, 255, 0, 0]), square(32, [255, 0, 0, 255])] if args.pixmaps else []
        self.attention = ""
        self.overlay = ""
        self.tooltip = [args.title, ""]

    @dbus_property(access=PropertyAccess.READ)
    def Category(self) -> "s":
        return self.args.category

    @dbus_property(access=PropertyAccess.READ)
    def Id(self) -> "s":
        return self.args.id

    @dbus_property(access=PropertyAccess.READ)
    def Title(self) -> "s":
        return self.title

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return self.status

    @dbus_property(access=PropertyAccess.READ)
    def WindowId(self) -> "i":
        return 0

    @dbus_property(access=PropertyAccess.READ)
    def IconName(self) -> "s":
        return self.icon_name

    @dbus_property(access=PropertyAccess.READ)
    def IconPixmap(self) -> "a(iiay)":
        return self.pixmaps

    @dbus_property(access=PropertyAccess.READ)
    def IconThemePath(self) -> "s":
        return self.args.theme_path

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconName(self) -> "s":
        return self.attention

    @dbus_property(access=PropertyAccess.READ)
    def AttentionIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconName(self) -> "s":
        return self.overlay

    @dbus_property(access=PropertyAccess.READ)
    def OverlayIconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def ToolTip(self) -> "(sa(iiay)ss)":
        return ["", [], self.tooltip[0], self.tooltip[1]]

    @dbus_property(access=PropertyAccess.READ)
    def ItemIsMenu(self) -> "b":
        return self.args.item_is_menu

    @dbus_property(access=PropertyAccess.READ)
    def Menu(self) -> "o":
        return "/MenuBar" if self.args.menu else "/NO_DBUSMENU"

    @method()
    def Activate(self, x: "i", y: "i"):
        log("CALL Activate", x, y)
        if self.args.no_activate:
            raise DBusError("org.freedesktop.DBus.Error.UnknownMethod", "No Activate here")

    @method()
    def SecondaryActivate(self, x: "i", y: "i"):
        log("CALL SecondaryActivate", x, y)

    @method()
    def ContextMenu(self, x: "i", y: "i"):
        log("CALL ContextMenu", x, y)

    @method()
    def Scroll(self, delta: "i", orientation: "s"):
        log("CALL Scroll", delta, orientation)

    @signal()
    def NewTitle(self):
        pass

    @signal()
    def NewIcon(self):
        pass

    @signal()
    def NewAttentionIcon(self):
        pass

    @signal()
    def NewOverlayIcon(self):
        pass

    @signal()
    def NewToolTip(self):
        pass

    @signal()
    def NewStatus(self, status) -> "s":
        return status


class Menu(ServiceInterface):
    """
    0 root
      1 _Show Window      2 separator        3 Mute (checkmark)
      4 _Quality > 5 Low (radio, on), 6 High (radio)
      7 Disabled (disabled)                  8 Hidden (invisible)
      9 Lazy > (filled by AboutToShow: 10 Loaded later)
      11 _Quit
    """

    def __init__(self):
        super().__init__("com.canonical.dbusmenu")
        self.revision = 1
        self.mute = 0
        self.lazy_filled = False
        self.extra = []

    def props(self, id_):
        return {
            1: {"label": Variant("s", "_Show Window"), "icon-name": Variant("s", "window-new")},
            2: {"type": Variant("s", "separator")},
            3: {"label": Variant("s", "Mute"), "toggle-type": Variant("s", "checkmark"),
                "toggle-state": Variant("i", self.mute)},
            4: {"label": Variant("s", "_Quality"), "children-display": Variant("s", "submenu")},
            5: {"label": Variant("s", "Low"), "toggle-type": Variant("s", "radio"), "toggle-state": Variant("i", 1)},
            6: {"label": Variant("s", "High"), "toggle-type": Variant("s", "radio"), "toggle-state": Variant("i", 0)},
            7: {"label": Variant("s", "Disabled"), "enabled": Variant("b", False)},
            8: {"label": Variant("s", "Hidden"), "visible": Variant("b", False)},
            9: {"label": Variant("s", "Lazy"), "children-display": Variant("s", "submenu")},
            10: {"label": Variant("s", "Loaded later")},
            11: {"label": Variant("s", "_Quit")},
        }.get(id_, {"label": Variant("s", f"Extra {id_}")})

    def node(self, id_, children=()):
        return Variant("(ia{sv}av)", [id_, self.props(id_), [self.node(*c) if isinstance(c, tuple) else self.node(c) for c in children]])

    def layout(self):
        lazy = (9, [10]) if self.lazy_filled else 9
        top = [1, 2, 3, (4, [5, 6]), 7, 8, lazy, *self.extra, 11]
        root = [0, {"children-display": Variant("s", "submenu")},
                [self.node(*c) if isinstance(c, tuple) else self.node(c) for c in top]]
        return root

    @method()
    def GetLayout(self, parent: "i", depth: "i", names: "as") -> "u(ia{sv}av)":
        log("CALL GetLayout", parent)
        return [self.revision, self.layout()]

    @method()
    def GetGroupProperties(self, ids: "ai", names: "as") -> "a(ia{sv})":
        return [[i, self.props(i)] for i in ids]

    @method()
    def GetProperty(self, id_: "i", name: "s") -> "v":
        return self.props(id_).get(name, Variant("s", ""))

    @method()
    def Event(self, id_: "i", event: "s", data: "v", timestamp: "u"):
        log("EVENT", id_, event)
        if event == "clicked" and id_ == 3:
            self.mute = 1 - self.mute
            self.ItemsPropertiesUpdated([[3, {"toggle-state": Variant("i", self.mute)}]], [])

    @method()
    def EventGroup(self, events: "a(isvu)") -> "ai":
        return []

    @method()
    def AboutToShow(self, id_: "i") -> "b":
        log("CALL AboutToShow", id_)
        if id_ == 9 and not self.lazy_filled:
            self.lazy_filled = True
            self.revision += 1
            self.LayoutUpdated(self.revision, 9)
            return True
        return False

    @method()
    def AboutToShowGroup(self, ids: "ai") -> "aiai":
        return [[], []]

    @dbus_property(access=PropertyAccess.READ)
    def Version(self) -> "u":
        return 3

    @dbus_property(access=PropertyAccess.READ)
    def TextDirection(self) -> "s":
        return "ltr"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return "normal"

    @dbus_property(access=PropertyAccess.READ)
    def IconThemePath(self) -> "as":
        return []

    @signal()
    def ItemsPropertiesUpdated(self, updated, removed) -> "a(ia{sv})a(ias)":
        return [updated, removed]

    @signal()
    def LayoutUpdated(self, revision, parent) -> "ui":
        return [revision, parent]

    def add(self, label):
        id_ = 100 + len(self.extra)
        self.extra.append(id_)
        self.revision += 1
        self.LayoutUpdated(self.revision, 0)


async def register(bus, value):
    try:
        await bus.call(Message(destination=WATCHER, path=WATCHER_PATH, interface=WATCHER,
                               member="RegisterStatusNotifierItem", signature="s", body=[value]))
        log("REGISTERED", value)
    except Exception as e:  # noqa: BLE001
        log("REGISTER FAILED", e)


def misbehave(bus, path, mode):
    """--evil answers GetAll with wrong types and never answers GetLayout;
    --silent never answers anything about its properties."""

    def handler(msg):
        if msg.message_type != MessageType.METHOD_CALL or msg.path not in (path, "/MenuBar"):
            return None
        if mode == "silent" and msg.interface == "org.freedesktop.DBus.Properties":
            log("SWALLOWED", msg.member)
            return True
        if mode == "evil":
            if msg.member == "GetAll":
                return Message.new_method_return(msg, "a{sv}", [{
                    "Status": Variant("i", 7),
                    "Title": Variant("as", ["not", "a", "string"]),
                    "IconPixmap": Variant("a(iiay)", [[64, 64, b"\x01\x02"], [-3, 2, b""]]),
                    "ToolTip": Variant("s", "a tooltip should be a struct"),
                    "Menu": Variant("s", "definitely not a path"),
                    "ItemIsMenu": Variant("s", "yes"),
                    "IconName": Variant("s", ""),
                }])
            if msg.member in ("GetLayout", "AboutToShow"):
                log("SWALLOWED", msg.member)
                return True
        return None

    bus.add_message_handler(handler)


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--register", choices=["path", "name", "none"], default="path")
    parser.add_argument("--id", default="test-item")
    parser.add_argument("--title", default="Test item")
    parser.add_argument("--status", default="Active")
    parser.add_argument("--category", default="ApplicationStatus")
    parser.add_argument("--icon", default="")
    parser.add_argument("--theme-path", default="")
    parser.add_argument("--pixmaps", action="store_true")
    parser.add_argument("--no-menu", dest="menu", action="store_false")
    parser.add_argument("--item-is-menu", action="store_true")
    parser.add_argument("--no-activate", action="store_true")
    parser.add_argument("--reregister", action="store_true",
                        help="register again when a watcher appears, like libappindicator")
    parser.add_argument("--misbehave", choices=["evil", "silent"])
    args = parser.parse_args()

    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    item = Item(args)
    menu = Menu()

    if args.register == "path":
        path = f"/org/ayatana/NotificationItem/{args.id.replace('-', '_')}"
        value = path
    else:
        path = "/StatusNotifierItem"
        value = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
        await bus.request_name(value)

    if args.misbehave:
        misbehave(bus, path, args.misbehave)
    bus.export(path, item)
    if args.menu:
        bus.export("/MenuBar", menu)

    if args.reregister:
        def on_owner(msg):
            if (msg.message_type == MessageType.SIGNAL and msg.member == "NameOwnerChanged"
                    and msg.body[0] == WATCHER and msg.body[2]):
                log("WATCHER APPEARED", msg.body[2])
                asyncio.ensure_future(register(bus, value))
            return None
        await bus.call(Message(destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                               interface="org.freedesktop.DBus", member="AddMatch", signature="s",
                               body=[f"type='signal',member='NameOwnerChanged',arg0='{WATCHER}'"]))
        bus.add_message_handler(on_owner)

    if args.register != "none":
        await register(bus, value)
    log("READY", bus.unique_name, value)

    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    while True:
        line = (await reader.readline()).decode()
        if not line:
            break
        command, _, rest = line.strip().partition(" ")
        if command == "status":
            item.status = rest
            item.NewStatus(rest)
        elif command == "title":
            item.title = rest
            item.NewTitle()
        elif command == "icon":
            item.icon_name = rest
            item.NewIcon()
        elif command == "pixmap":
            item.icon_name = ""
            item.pixmaps = [square(int(rest), [255, 0, 255, 0])]
            item.NewIcon()
        elif command == "attention":
            item.attention = rest
            item.NewAttentionIcon()
        elif command == "overlay":
            item.overlay = rest
            item.NewOverlayIcon()
        elif command == "tooltip":
            title, _, description = rest.partition("|")
            item.tooltip = [title, description]
            item.NewToolTip()
        elif command == "addmenu":
            menu.add(rest)
        elif command == "quit":
            break
        log("DONE", command)


asyncio.run(main())
