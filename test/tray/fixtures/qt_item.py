#!/usr/bin/env python3
"""A Qt QSystemTrayIcon (what Telegram, Nextcloud, KeePassXC and other Qt
apps use): registered by bus name, an icon as pixmaps only, a QMenu exported
over Qt's own dbusmenu, filled further when it's about to show. Logs what it
gets on stdout, takes commands on stdin: color NAME, tooltip TEXT, quit.

Needs python3-pyqt6 and a display (QT_QPA_PLATFORM=xcb on an Xvfb). Run it
on a private bus only.
"""

import sys

from PyQt6.QtCore import QSocketNotifier
from PyQt6.QtGui import QColor, QIcon, QPixmap
from PyQt6.QtWidgets import QApplication, QMenu, QSystemTrayIcon


def log(*parts):
    print(*parts, flush=True)


def icon(color):
    result = QIcon()
    for size in (16, 22, 32, 48):
        pixmap = QPixmap(size, size)
        pixmap.fill(QColor(color))
        result.addPixmap(pixmap)
    return result


app = QApplication(sys.argv)
app.setQuitOnLastWindowClosed(False)

tray = QSystemTrayIcon(icon("#2a9d8f"))
tray.setToolTip("Qt test item")

menu = QMenu()
menu.addAction("Open &Qt app").triggered.connect(lambda: log("ACTIVATED open"))
sync = menu.addAction("Pause sync")
sync.setCheckable(True)
sync.toggled.connect(lambda on: log("TOGGLED sync", on))
menu.addSeparator()
recent = menu.addMenu("Recent files")
recent.aboutToShow.connect(lambda: log("ABOUTTOSHOW recent"))
recent.addAction("notes.txt").triggered.connect(lambda: log("ACTIVATED notes"))
menu.addSeparator()
menu.addAction("&Quit").triggered.connect(lambda: (log("ACTIVATED quit"), app.quit()))
shown = [0]


def about_to_show():
    shown[0] += 1
    log("ABOUTTOSHOW menu", shown[0])


menu.aboutToShow.connect(about_to_show)
tray.setContextMenu(menu)
tray.activated.connect(lambda reason: log("ACTIVATED tray", reason.name))
tray.show()


def on_input():
    line = sys.stdin.readline()
    if not line:
        app.quit()
        return
    command, _, rest = line.strip().partition(" ")
    if command == "color":
        tray.setIcon(icon(rest))
    elif command == "tooltip":
        tray.setToolTip(rest)
    elif command == "quit":
        app.quit()
        return
    log("DONE", command)


notifier = QSocketNotifier(sys.stdin.fileno(), QSocketNotifier.Type.Read)
notifier.activated.connect(on_input)
log("READY", QSystemTrayIcon.isSystemTrayAvailable())
app.exec()
