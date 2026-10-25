#!/usr/bin/env python3
"""A real libayatana-appindicator item (what Steam, Nextcloud's GTK builds,
nm-applet --indicator and most GTK apps use), with a GTK menu exported over
libdbusmenu. Logs what it gets on stdout, takes commands on stdin:

  status passive|active|attention   icon NAME   label TEXT   addmenu LABEL   quit

Needs gir1.2-ayatanaappindicator3-0.1 and a display for GTK (DISPLAY=:N of
an Xvfb is enough). Run it on a private bus only.
"""

import argparse
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import AyatanaAppIndicator3 as AppIndicator  # noqa: E402
from gi.repository import GLib, Gtk  # noqa: E402


def log(*parts):
    print(*parts, flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--id", default="ayatana-test")
    parser.add_argument("--icon", default="network-wireless-signal-good-symbolic")
    parser.add_argument("--theme-path", default="")
    parser.add_argument("--title", default="Ayatana test")
    args = parser.parse_args()

    indicator = AppIndicator.Indicator.new(
        args.id, args.icon, AppIndicator.IndicatorCategory.APPLICATION_STATUS)
    if args.theme_path:
        indicator.set_icon_theme_path(args.theme_path)
    indicator.set_title(args.title)
    indicator.set_attention_icon_full("mail-unread-symbolic", "New mail")
    indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)

    menu = Gtk.Menu()

    def item(widget, name):
        widget.connect("activate", lambda *_: log("ACTIVATED", name))
        menu.append(widget)
        return widget

    show = item(Gtk.MenuItem.new_with_mnemonic("_Show Window"), "show")
    dnd = Gtk.CheckMenuItem.new_with_label("Do not disturb")
    dnd.connect("toggled", lambda w: log("TOGGLED dnd", w.get_active()))
    menu.append(dnd)
    menu.append(Gtk.SeparatorMenuItem())
    online = Gtk.RadioMenuItem.new_with_label(None, "Online")
    away = Gtk.RadioMenuItem.new_with_label_from_widget(online, "Away")
    online.set_active(True)
    for widget, name in ((online, "online"), (away, "away")):
        widget.connect("toggled", lambda w, n=name: w.get_active() and log("RADIO", n))
        menu.append(widget)
    more = Gtk.MenuItem.new_with_label("More")
    submenu = Gtk.Menu()
    nested = Gtk.MenuItem.new_with_label("Nested item")
    nested.connect("activate", lambda *_: log("ACTIVATED nested"))
    submenu.append(nested)
    more.set_submenu(submenu)
    menu.append(more)
    unavailable = Gtk.MenuItem.new_with_label("Unavailable")
    unavailable.set_sensitive(False)
    menu.append(unavailable)
    menu.append(Gtk.SeparatorMenuItem())
    item(Gtk.MenuItem.new_with_mnemonic("_Quit"), "quit")
    menu.show_all()

    indicator.set_menu(menu)
    indicator.set_secondary_activate_target(show)
    indicator.connect("scroll-event", lambda _i, delta, direction: log("SCROLL", delta, direction.value_nick))

    def on_input(source, _condition):
        line = source.readline()
        if not line:
            Gtk.main_quit()
            return False
        command, _, rest = line.strip().partition(" ")
        if command == "status":
            indicator.set_status({
                "passive": AppIndicator.IndicatorStatus.PASSIVE,
                "active": AppIndicator.IndicatorStatus.ACTIVE,
                "attention": AppIndicator.IndicatorStatus.ATTENTION,
            }[rest])
        elif command == "icon":
            indicator.set_icon_full(rest, rest)
        elif command == "label":
            indicator.set_title(rest)
        elif command == "addmenu":
            extra = Gtk.MenuItem.new_with_label(rest)
            extra.connect("activate", lambda *_: log("ACTIVATED", rest))
            extra.show()
            menu.insert(extra, 0)
        elif command == "quit":
            Gtk.main_quit()
            return False
        log("DONE", command)
        return True

    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, on_input)
    log("READY", args.id)
    Gtk.main()


main()
