# dahliaOS application icons

Official dahliaOS application icons ("plastic" set) from
https://github.com/dahliaOS/icons, licensed under the Apache License 2.0.

`svg/` holds the original artwork. The `hicolor/` PNG renditions are what
gets installed: the SVGs rely on masks and filters that Flutter's SVG renderer
(jovial_svg, used by Pangolin and the apps) does not support, so they are
pre-rendered with a full SVG engine.

The official set has no Disks icon: `io.dahliaos.disks.svg` is Pangolin's own,
drawn in the same style. The PNGs are rendered with
`rsvg-convert -w N -h N io.dahliaos.disks.svg`, which gives the official
icons' PNGs back unchanged.
