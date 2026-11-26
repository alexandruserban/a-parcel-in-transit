"""Export the web game's procedural textures to assets/textures/ as PNGs.

Runs tools/export_textures.html in headless Chrome. The page loads ../tidyup/js/textures.js (and the files
that extend it), draws every texture the Godot port uses, and puts each one in the DOM as a PNG data URL.
This script reads the DOM back and writes the files.

    python tools/export_textures.py [path-to-chrome] [--only name1,name2]

The ../tidyup checkout must sit next to this project.
"""
import base64
import html
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGE = ROOT / "tools" / "export_textures.html"
OUT = ROOT / "assets" / "textures"
CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]


# --only a,b writes just those textures (the generators are random, so a full run changes every file)
ONLY = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else set()
ARGS = [a for i, a in enumerate(sys.argv[1:], 1) if a != "--only" and sys.argv[i - 1] != "--only"]


def find_chrome() -> str:
    if ARGS:
        return ARGS[0]
    for c in CHROME_CANDIDATES:
        if Path(c).exists():
            return c
    sys.exit("Chrome or Edge not found: pass its path as the first argument")


def main() -> None:
    chrome = find_chrome()
    cmd = [chrome, "--headless=new", "--disable-gpu", "--allow-file-access-from-files",
           "--virtual-time-budget=600000", "--run-all-compositor-stages-before-draw",
           "--dump-dom", PAGE.as_uri()]
    print("Rendering textures in headless Chrome (this takes a minute)...")
    dom = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=900).stdout
    err = re.search(r'data-error="([^"]*)"', dom)
    if err:
        sys.exit("Texture page failed:\n" + html.unescape(err.group(1)))
    if 'data-done="1"' not in dom:
        sys.exit("Texture page did not finish (got %d bytes of DOM)" % len(dom))
    OUT.mkdir(parents=True, exist_ok=True)
    count = 0
    for name, url in re.findall(r'<pre data-name="([^"]+)">data:image/png;base64,([^<]+)</pre>', dom):
        if ONLY and name not in ONLY:
            continue
        path = OUT / (name + ".png")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(base64.b64decode(url))
        count += 1
    print("Wrote %d textures to %s" % (count, OUT))


if __name__ == "__main__":
    main()
