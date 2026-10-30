#!/usr/bin/env python3
"""Resimleri kullanıcıya göstermek için tek dosyalık inceleme sayfası yapar ve Safari'de açar.
Resimler sayfanın içine gömülür (base64): Safari yerel sayfanın başka klasördeki resimlerini
güvenlik için göstermez; gömülü resim her zaman görünür.
Kullanım: inceleme-ac.py "Başlık" [--acik] resim1.png "Bölüm adı=resim2.png" klasör/ ...
  --acik: sonraki resimler beyaz zeminde (açık tema önizlemesi)."""
import base64, html, mimetypes, os, subprocess, sys, tempfile, time

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    title, items, light = sys.argv[1], [], False
    for arg in sys.argv[2:]:
        if arg == "--acik": light = True; continue
        if arg == "--koyu": light = False; continue
        name, _, path = arg.rpartition("=") if "=" in arg else ("", "", arg)
        paths = sorted(os.path.join(path, f) for f in os.listdir(path)
                       if f.lower().endswith((".png", ".jpg", ".jpeg", ".gif"))) if os.path.isdir(path) else [path]
        for p in paths:
            if not os.path.isfile(p): sys.exit(f"Bulunamadı: {p}")
            items.append((name or os.path.basename(p), p, light))
    blocks = []
    for name, p, lt in items:
        mime = mimetypes.guess_type(p)[0] or "image/png"
        data = base64.b64encode(open(p, "rb").read()).decode()
        bg = "background:#fff;padding:16px;border-radius:8px" if lt else ""
        blocks.append(f'<section><h3>{html.escape(name)}</h3><div style="{bg}"><img src="data:{mime};base64,{data}"></div></section>')
    page = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>{html.escape(title)}</title><style>
body{{background:#0d1117;color:#e6edf3;font-family:-apple-system,sans-serif;margin:0 auto;padding:28px;max-width:1300px}}
img{{max-width:100%;display:block;border-radius:6px}} h3{{margin:26px 0 8px;font-weight:600}}
</style></head><body><h1>{html.escape(title)}</h1>{''.join(blocks)}</body></html>"""
    out = os.path.join(tempfile.gettempdir(), f"inceleme-{int(time.time())}.html")
    open(out, "w").write(page)
    subprocess.run(["open", "-a", "Safari", out], check=True)
    print(f"Açıldı: {out} ({len(items)} resim)")

main()
