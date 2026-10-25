#!/usr/bin/env python3
"""A bare org.kde.StatusNotifierWatcher (like kded's), for testing Pangolin
as a host of another watcher. Logs registrations on stdout; exits when stdin
closes. Needs python3-dbus-next. Run it on a private bus only."""

import asyncio
import sys

from dbus_next import BusType
from dbus_next.aio import MessageBus
from dbus_next.constants import NameFlag, RequestNameReply
from dbus_next.service import PropertyAccess, ServiceInterface, dbus_property, method, signal


class Watcher(ServiceInterface):
    def __init__(self):
        super().__init__("org.kde.StatusNotifierWatcher")
        self.items = []
        self.hosts = []

    @method()
    def RegisterStatusNotifierItem(self, service: "s"):
        # Like kded: the sender owns items given by path. dbus-next doesn't
        # give the sender here, so tests register "service/path" or names.
        entry = service if "/" in service else service + "/StatusNotifierItem"
        if entry not in self.items:
            self.items.append(entry)
            self.StatusNotifierItemRegistered(entry)
        print("ITEM", entry, flush=True)

    @method()
    def RegisterStatusNotifierHost(self, service: "s"):
        self.hosts.append(service)
        print("HOST", service, flush=True)
        self.StatusNotifierHostRegistered()

    @dbus_property(access=PropertyAccess.READ)
    def RegisteredStatusNotifierItems(self) -> "as":
        return self.items

    @dbus_property(access=PropertyAccess.READ)
    def IsStatusNotifierHostRegistered(self) -> "b":
        return bool(self.hosts)

    @dbus_property(access=PropertyAccess.READ)
    def ProtocolVersion(self) -> "i":
        return 0

    @signal()
    def StatusNotifierItemRegistered(self, service) -> "s":
        return service

    @signal()
    def StatusNotifierItemUnregistered(self, service) -> "s":
        return service

    @signal()
    def StatusNotifierHostRegistered(self):
        pass


async def main():
    bus = await MessageBus(bus_type=BusType.SESSION).connect()
    watcher = Watcher()
    bus.export("/StatusNotifierWatcher", watcher)
    reply = await bus.request_name("org.kde.StatusNotifierWatcher", NameFlag.DO_NOT_QUEUE)
    print("WATCHER", reply == RequestNameReply.PRIMARY_OWNER, bus.unique_name, flush=True)

    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    while True:
        line = (await reader.readline()).decode().strip()
        if not line:
            break
        if line.startswith("unregister "):
            entry = line.split(" ", 1)[1]
            if entry in watcher.items:
                watcher.items.remove(entry)
            watcher.StatusNotifierItemUnregistered(entry)
            print("DONE unregister", flush=True)


asyncio.run(main())
