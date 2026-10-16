"""Write installer Finder metadata directly; no Automation permission needed.

Build-only dependencies vendored under Scripts/vendor: ds_store 1.3.3 and
mac_alias 2.2.2 (MIT). No third-party code is shipped in NimBar.app.
"""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent / "vendor"))
from ds_store import DSStore
from mac_alias import Alias

volume = Path(sys.argv[1])
background = Alias.for_file(str(volume / ".background" / "installer.png")).to_bytes()
with DSStore.open(str(volume / ".DS_Store"), "w+") as store:
    store["."]["bwsp"] = {
        "ShowStatusBar": False, "ShowToolbar": False, "ShowSidebar": False,
        "ContainerShowSidebar": False, "PreviewPaneVisibility": False,
        "ShowTabView": False, "ShowPathbar": False, "SidebarWidth": 0,
        "WindowBounds": "{{200, 200}, {582, 300}}",
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1, "backgroundType": 2,
        "backgroundColorRed": 1.0, "backgroundColorGreen": 1.0, "backgroundColorBlue": 1.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        "backgroundImageAlias": background, "iconSize": 100.0,
        "textSize": 12.0, "arrangeBy": "none", "gridOffsetX": 0.0,
        "gridOffsetY": 0.0, "gridSpacing": 100.0, "labelOnBottom": True,
        "showIconPreview": True, "showItemInfo": False,
    }
    store["."]["vSrn"] = ("long", 1)
    store["."]["icvl"] = ("type", b"icnv")
    store["NimBar.app"]["Iloc"] = (150, 150)
    store["Applications"]["Iloc"] = (436, 150)
