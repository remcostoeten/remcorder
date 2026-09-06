#!/usr/bin/env python3
"""Render release artwork from the existing application mark with librsvg."""

import base64
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "docs" / "assets"


def embedded_png(path):
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def svg_document(width, height, title, content):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title">
<title id="title">{title}</title>
<rect width="{width}" height="{height}" fill="#0d0d0f"/>
{content}
</svg>
'''


def render(name, source):
    svg_path = ASSETS / f"{name}.svg"
    svg_path.write_text(source)
    subprocess.run([
        "rsvg-convert", "--output", str(ASSETS / f"{name}.png"), str(svg_path)
    ], check=True)
    print(f"Rendered {name}")


def main():
    if shutil.which("rsvg-convert") is None:
        raise SystemExit("Install librsvg (rsvg-convert) to render release artwork.")
    ASSETS.mkdir(parents=True, exist_ok=True)
    icon = embedded_png(ROOT / "packaging/icons/remcorder-512.png")
    screenshot = embedded_png(ASSETS / "app.png")
    render("readme-banner", svg_document(1600, 480, "Remcorder — Screen recording for Linux", f'''
<path d="M48 104V48H104 M1496 48H1552V104 M1552 376V432H1496 M104 432H48V376" fill="none" stroke="#49414f" stroke-width="2"/>
<circle cx="110" cy="113" r="7" fill="#e34c26"/>
<text x="134" y="120" fill="#a1a1aa" font-family="JetBrains Mono, monospace" font-size="19" letter-spacing="2">SCREEN RECORDING FOR LINUX</text>
<text x="99" y="259" fill="#fafafa" font-family="Inter, sans-serif" font-size="116" font-weight="650" letter-spacing="-6">Remcorder</text>
<text x="105" y="332" fill="#a1a1aa" font-family="Inter, sans-serif" font-size="28">Pick a screen. Hit record. Trim the result.</text>
<image x="1140" y="70" width="340" height="340" xlink:href="{icon}"/>
'''))
    render("social-preview", svg_document(1280, 640, "Remcorder — Linux screen recorder with tray controls and a CLI", f'''
<path d="M32 80V32H80 M1200 32H1248V80 M1248 560V608H1200 M80 608H32V560" fill="none" stroke="#49414f" stroke-width="2"/>
<image x="62" y="69" width="82" height="82" xlink:href="{icon}"/>
<text x="163" y="119" fill="#a1a1aa" font-family="JetBrains Mono, monospace" font-size="16" letter-spacing="1">SCREEN RECORDING / LINUX</text>
<text x="67" y="255" fill="#fafafa" font-family="Inter, sans-serif" font-size="76" font-weight="650" letter-spacing="-4">Remcorder</text>
<text x="72" y="324" fill="#d4d4d8" font-family="Inter, sans-serif" font-size="28">Pick a screen. Hit record.</text>
<text x="72" y="365" fill="#d4d4d8" font-family="Inter, sans-serif" font-size="28">Trim the result.</text>
<text x="72" y="443" fill="#a1a1aa" font-family="Inter, sans-serif" font-size="20">A Qt app, tray controls, and a CLI.</text>
<rect x="630" y="154" width="584" height="365" rx="20" fill="#19171d"/>
<image x="648" y="178" width="548" height="320" preserveAspectRatio="xMidYMid meet" xlink:href="{screenshot}"/>
<circle cx="80" cy="558" r="5" fill="#e34c26"/>
<text x="99" y="565" fill="#a1a1aa" font-family="JetBrains Mono, monospace" font-size="17">github.com/remcostoeten/remcorder</text>
'''))


if __name__ == "__main__":
    main()
