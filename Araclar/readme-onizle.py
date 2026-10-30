#!/usr/bin/env python3
"""README'yi GitHub'ın kendi biçimlendiricisiyle (gh api markdown) çevirir, açık ve koyu tema
iki sekme olarak tek dosyalık sayfa yapar ve Safari'de açar. Resimler sayfaya gömülür
(Safari yerel sayfanın başka klasördeki resimlerini göstermez). Kullanım: readme-onizle.py [README.md]"""
import base64, json, mimetypes, os, re, subprocess, sys, tempfile, time, urllib.request

readme = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "README.md")
root = os.path.dirname(readme)
body = subprocess.run(["gh", "api", "markdown", "--input", "-"], check=True, capture_output=True,
                      input=json.dumps({"text": open(readme).read(), "mode": "gfm", "context": "enisaytac/FingerKit"}).encode()).stdout.decode()

def embed(m):
    attr, src = m.group(1), m.group(2)
    if src.startswith(("http", "data:", "#")): return m.group(0)
    p = os.path.join(root, src)
    if not os.path.isfile(p): return m.group(0)
    data = base64.b64encode(open(p, "rb").read()).decode()
    return f'{attr}="data:{mimetypes.guess_type(p)[0]};base64,{data}"'
body = re.sub(r'(src|srcset)="([^"]+)"', embed, body)

def css(theme):
    url = f"https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.8.1/github-markdown-{theme}.min.css"
    return urllib.request.urlopen(url).read().decode()

def page(theme):
    b = body
    if theme == "light":  # <picture> içindeki koyu kaynak açık temada seçilmez
        b = re.sub(r'<source media="\(prefers-color-scheme: dark\)"[^>]*>', "", b)
    else:
        b = re.sub(r'<source media="\(prefers-color-scheme: dark\)" srcset="([^"]+)"[^>]*>\s*<img src="[^"]+"', r'<img src="\1"', b)
    bg = "#ffffff" if theme == "light" else "#0d1117"
    return f'<div class="tema" id="{theme}" style="background:{bg}"><article class="markdown-body markdown-{theme}">{b}</article></div>'

style = css("light").replace(".markdown-body", ".markdown-light") + css("dark").replace(".markdown-body", ".markdown-dark")
html = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>README önizleme</title><style>{style}
body{{margin:0;font-family:-apple-system}} .ust{{position:sticky;top:0;z-index:9;background:#222;padding:10px;text-align:center}}
.ust button{{font-size:15px;margin:0 6px;padding:6px 16px;border-radius:8px;border:0;cursor:pointer}}
.tema{{padding:32px 0;min-height:100vh}} article{{max-width:980px;margin:auto;padding:0 32px;box-sizing:border-box}} .gizli{{display:none}}
</style></head><body><div class="ust"><button onclick="g('light')">Açık tema (beyaz)</button><button onclick="g('dark')">Koyu tema (gece)</button></div>
{page('dark')}{page('light')}
<script>function g(t){{for(const d of document.querySelectorAll('.tema'))d.classList.toggle('gizli',d.id!==t);scrollTo(0,0)}}g('dark')</script></body></html>"""
out = os.path.join(tempfile.gettempdir(), f"readme-onizleme-{int(time.time())}.html")
open(out, "w").write(html)
subprocess.run(["open", "-a", "Safari", out], check=True)
print("Açıldı:", out)
