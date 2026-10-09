# -*- coding: utf-8 -*-
"""Assemble l'application : version Artifact (sans squelette) et version autonome pour Safari."""
import base64, io, pathlib, re
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent
src = (ROOT / "src" / "app.html").read_text(encoding="utf-8")

im = Image.open(ROOT.parent / "assets" / "logo_source.png").convert("RGBA")
im = im.crop(im.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox())
im.thumbnail((130, 160), Image.LANCZOS)
buf = io.BytesIO(); im.save(buf, "PNG", optimize=True)
logo = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()
page = src.replace("__LOGO__", logo)

(ROOT / "bibliotheque.html").write_text(page, encoding="utf-8")

head_tags = re.findall(r"^(<title>.*?</title>|<link [^>]*>)\s*$", page, flags=re.M)
body = re.sub(r"^(<title>.*?</title>|<link [^>]*>)\s*\n", "", page, flags=re.M)
standalone = ("<!doctype html>\n<html lang=\"fr\">\n<head>\n<meta charset=\"utf-8\">\n"
              "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">\n"
              "<meta name=\"apple-mobile-web-app-capable\" content=\"yes\">\n"
              "<meta name=\"apple-mobile-web-app-title\" content=\"Bibliothèque KIS\">\n"
              f"<link rel=\"apple-touch-icon\" href=\"{logo}\">\n" + "\n".join(head_tags) +
              "\n</head>\n<body>\n" + body + "\n</body>\n</html>\n")
(ROOT.parent / "Bibliotheque_KIS.html").write_text(standalone, encoding="utf-8")
print("OK", len(page), len(standalone))
