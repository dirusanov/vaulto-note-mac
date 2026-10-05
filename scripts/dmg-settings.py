# dmgbuild settings for Vaulto Note. Used by scripts/package-release.sh:
#   dmgbuild -s scripts/dmg-settings.py -D app=<path.app> -D background=<tiff> "Vaulto Note" out.dmg
import os

application = defines["app"]  # noqa: F821 — injected by dmgbuild
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {appname: (170, 190), "Applications": (490, 190)}
background = defines["background"]  # noqa: F821
window_rect = ((200, 120), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
badge_icon = os.path.join(application, "Contents/Resources/AppIcon.icns")
