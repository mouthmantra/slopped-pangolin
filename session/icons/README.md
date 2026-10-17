# dahliaOS application icons

Official dahliaOS application icons ("plastic" set) from
https://github.com/dahliaOS/icons, licensed under the Apache License 2.0.

`svg/` holds the original artwork. The `hicolor/` PNG renditions are what
gets installed: the SVGs rely on masks and filters that Flutter's SVG renderer
(jovial_svg, used by Pangolin and the apps) does not support, so they are
pre-rendered with a full SVG engine.
