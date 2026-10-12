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
CDN_PDF = ('<script src="https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js"></script>\n'
           '<script src="https://cdn.jsdelivr.net/npm/jspdf-autotable@3.8.4/dist/jspdf.plugin.autotable.min.js"></script>')
VENDOR = ROOT.parent / "web" / "vendor"
page = page.replace("<!--VENDOR-->", CDN_PDF)

(ROOT / "bibliotheque.html").write_text(page, encoding="utf-8")

head_tags = re.findall(r"^(<title>.*?</title>|<link [^>]*>)\s*$", page, flags=re.M)
body = re.sub(r"^(<title>.*?</title>|<link [^>]*>)\s*\n", "", page, flags=re.M)
standalone = ("<!doctype html>\n<html lang=\"fr\">\n<head>\n<meta charset=\"utf-8\">\n"
              "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">\n"
              "<meta name=\"apple-mobile-web-app-capable\" content=\"yes\">\n"
              "<meta name=\"apple-mobile-web-app-title\" content=\"Kivuthèque\">\n"
              f"<link rel=\"apple-touch-icon\" href=\"{logo}\">\n" + "\n".join(head_tags) +
              "\n</head>\n<body>\n" + body + "\n</body>\n</html>\n")
(ROOT.parent / "Bibliotheque_KIS.html").write_text(standalone, encoding="utf-8")
print("OK", len(page), len(standalone))

# ---------------------------------------------------------------- version de bureau (Electron)
import urllib.request
DESK = ROOT.parent / "desktop"
FONT_CACHE = ROOT / "fonts"
FONT_CACHE.mkdir(exist_ok=True)
css_url = re.search(r'href="(https://fonts\.googleapis\.com/css2[^"]+)"', standalone).group(1).replace("&amp;", "&")
font_css_file = FONT_CACHE / "bricolage.css"
if not font_css_file.exists():
    req = urllib.request.Request(css_url, headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"})
    font_css = urllib.request.urlopen(req, timeout=30).read().decode()
    # on ne garde que le sous-ensemble latin (français)
    blocks = re.findall(r"/\* ([a-z-]+) \*/\s*(@font-face \{.*?\})", font_css, flags=re.S)
    keep = [b for name, b in blocks if name == "latin"] or [b for _, b in blocks]
    out = []
    for b in keep:
        url = re.search(r"url\((https://[^)]+)\)", b).group(1)
        data = urllib.request.urlopen(url, timeout=30).read()
        out.append(b.replace(url, "data:font/woff2;base64," + base64.b64encode(data).decode()))
    font_css_file.write_text("\n".join(out), encoding="utf-8")
font_css = font_css_file.read_text(encoding="utf-8")
desk = re.sub(r'<link rel="preconnect"[^>]*>\n?', "", standalone)
desk = re.sub(r'<link rel="stylesheet" href="https://fonts\.googleapis\.com[^"]*">', "<style>" + font_css + "</style>", desk)
desk = desk.replace('<meta charset="utf-8">', '<meta charset="utf-8">\n<meta http-equiv="Content-Security-Policy" content="default-src \'self\' data: blob:; style-src \'self\' \'unsafe-inline\' data:; script-src \'self\' \'unsafe-inline\'; img-src \'self\' data: blob:; font-src data:">')
inline = "".join("<script>" + (VENDOR / f).read_text(encoding="utf-8").replace("</script", "<\\/script") + "</script>\n"
                 for f in ("jspdf.umd.min.js", "jspdf.plugin.autotable.min.js"))
assert CDN_PDF in desk
desk = desk.replace(CDN_PDF, inline)
(DESK / "index.html").write_text(desk, encoding="utf-8")

# icône : logo sur fond blanc arrondi, 1024 px
from PIL import ImageDraw
src = Image.open(ROOT.parent / "assets" / "logo_source.png").convert("RGBA")
src = src.crop(src.split()[3].point(lambda v: 255 if v > 20 else 0).getbbox())
S_ = 1024
icon = Image.new("RGBA", (S_, S_), (0, 0, 0, 0))
mask = Image.new("L", (S_, S_), 0)
ImageDraw.Draw(mask).rounded_rectangle((100, 100, S_ - 100, S_ - 100), radius=185, fill=255)
icon.paste(Image.new("RGBA", (S_, S_), (255, 255, 255, 255)), (0, 0), mask)
src.thumbnail((620, 620), Image.LANCZOS)
icon.alpha_composite(src, ((S_ - src.width) // 2, (S_ - src.height) // 2))
(DESK / "build").mkdir(exist_ok=True)
icon.save(DESK / "build" / "icon.png")
print("Bureau OK", len(desk))

# ---------------------------------------------------------------- version en ligne (Netlify + Supabase)
WEB = ROOT.parent / "web"
local = ('<script src="vendor/jspdf.umd.min.js"></script>\n<script src="vendor/jspdf.plugin.autotable.min.js"></script>\n'
         '<script src="vendor/supabase.js"></script>\n<script src="config.js"></script>')
web = standalone.replace(CDN_PDF, local)
web = web.replace('<meta charset="utf-8">', '<meta charset="utf-8">\n<meta name="robots" content="noindex">\n<meta name="theme-color" content="#00AEEF">\n<link rel="icon" type="image/png" href="icon.png">\n<link rel="manifest" href="manifest.webmanifest">')
(WEB / "index.html").write_text(web, encoding="utf-8")
cfg = WEB / "config.js"
if not cfg.exists():
    cfg.write_text('// Connexion au projet Supabase (Supabase › Project Settings › API).\n'
                   '// La clé « anon / publishable » est publique par conception : la sécurité est assurée par les règles de la base.\n'
                   'window.KIV_CONFIG = {\n  supabaseUrl: "https://VOTRE-PROJET.supabase.co",\n  supabaseKey: "VOTRE-CLE-PUBLIQUE"\n};\n', encoding="utf-8")
ic_ = Image.open(DESK / "build" / "icon.png"); ic_.resize((512, 512), Image.LANCZOS).save(WEB / "icon.png")
(WEB / "manifest.webmanifest").write_text('{"name":"Kivuthèque","short_name":"Kivuthèque","start_url":"./","display":"standalone",'
                                          '"background_color":"#EDF2F7","theme_color":"#00AEEF","lang":"fr",'
                                          '"icons":[{"src":"icon.png","sizes":"512x512","type":"image/png","purpose":"any"}]}', encoding="utf-8")
print("Web OK", len(web))
