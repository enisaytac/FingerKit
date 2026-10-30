#!/usr/bin/env python3
"""Checks that every language in Paket/Diller has a translation for every UI string.

Keys come from the Swift compiler itself (-emit-localized-strings), so nothing is guessed.
Run from the package root:  python3 Araclar/dilleri-denetle.py
Exit code 1 if a language is missing keys or a translation has the wrong placeholders.

Arayüz metinlerinin her dilde çevirisi var mı bakar. Kaynak dil Türkçe; anahtar Türkçe metindir.
"""
import glob, json, os, re, subprocess, sys, tempfile

# Enum ham değerleri (rawValue) derleyicinin çıkaramadığı metinlerdir; elle eklenir
EXTRA_KEYS = {"İzleme Dörtgeni", "Hiper Tuş", "Pano", "Kısayol Tuşları", "Daire menü",
              "Tuş birleşimi", "Caps Lock + tuş", "Kısayol gönder", "Menü maddesi", "Hazır iş"}
# Çevirisi gerekmeyen metinler (yalnız sayı, simge ya da uygulama adı)
NEUTRAL = re.compile(r'^[\s%@ld·/()+]*$|^FingerKit$')
PLACEHOLDER = re.compile(r'%(?:\d+\$)?(?:lld|@|d|f|lf)')


def extract(target, touch_dir):
    """Bir hedefi derleyip çıkan .stringsdata anahtarlarını döner"""
    out = tempfile.mkdtemp()
    for f in glob.glob(f'Sources/{touch_dir}/**/*.swift', recursive=True):
        os.utime(f)
    subprocess.run(['swift', 'build', '--target', target,
                    '-Xswiftc', '-emit-localized-strings',
                    '-Xswiftc', '-emit-localized-strings-path', '-Xswiftc', out],
                   check=True, stdout=subprocess.DEVNULL)
    keys = set()
    for f in glob.glob(f'{out}/*.stringsdata'):
        for entries in json.load(open(f))['tables'].values():
            keys.update(e['key'] for e in entries)
    return keys


def load_strings(path):
    data = subprocess.run(['plutil', '-convert', 'json', '-o', '-', path],
                          check=True, capture_output=True).stdout
    return json.loads(data)


def main():
    # Aynı adlı dosyalar (RadialMenu.swift iki modülde) çıktıda çakışır; modüller ayrı derlenir
    keys = extract('FingerKit', 'FingerKit') | extract('FingerKitCore', 'FingerKitCore') | EXTRA_KEYS
    keys = {k for k in keys if not NEUTRAL.match(k)}
    failed = False
    for path in sorted(glob.glob('Paket/Diller/*.lproj/Localizable.strings')):
        lang = path.split('/')[-2].removesuffix('.lproj')
        table = load_strings(path)
        missing = sorted(keys - table.keys())
        unused = sorted(table.keys() - keys)
        wrong = [k for k in keys & table.keys()
                 if sorted(PLACEHOLDER.findall(k)) != sorted(PLACEHOLDER.findall(table[k]))]
        status = 'ok' if not (missing or wrong) else 'EKSİK / MISSING'
        print(f'{lang:8} {len(keys & table.keys())}/{len(keys)} {status}')
        for k in missing: print(f'   missing: {k!r}')
        for k in wrong: print(f'   placeholders differ: {k!r} -> {table[k]!r}')
        for k in unused: print(f'   unused (can be deleted): {k!r}')
        failed |= bool(missing or wrong)
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
