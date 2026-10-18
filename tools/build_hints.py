#!/usr/bin/env python3
"""tools/hints/*.json içindeki ipuçlarını Atlas/Resources/hints.json'da birleştirir.

Her il (plaka kodu) ve ülke (ADM0_A3 kodu) için 6 dilde 3 ipucu vardır; ilk ipucu en genel,
sonuncusu en belirgin olandır. Betik eksik yer/dil olup olmadığını ve ipuçlarında yerin
kendi adının geçip geçmediğini denetler.

Kullanım: python3 tools/build_hints.py && cp Atlas/Resources/hints.json web/data/
"""
import glob
import json
import os
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "Atlas", "Resources")
LANGS = ["tr", "en", "de", "fr", "es", "it"]
# Bilerek geçen adlar: başkent adı (Brasília, San Salvador) ya da başka anlamdaki kelime
# (İngilizce "island" ↔ Almanca İzlanda). Değer, adın geçmesine izin verilen diller.
ALLOW = {("BRA", "Brasil"): LANGS, ("SLV", "Salvador"): LANGS, ("ISL", "Island"): ["tr", "en", "fr", "es", "it"]}


def load(pattern):
    merged = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "tools", "hints", pattern))):
        merged.update(json.load(open(path, encoding="utf-8")))
    return merged


def norm(s):
    s = s.replace("İ", "i").replace("I", "ı").lower().replace("ı", "i")
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")


def check(kind, hints, places):
    errors = []
    for key, names in places.items():
        h = hints.get(key)
        if not h:
            errors.append(f"{kind} {key}: ipucu yok")
            continue
        for lang in LANGS:
            if len(h.get(lang, [])) != 3 or not all(h[lang]):
                errors.append(f"{kind} {key}: {lang} dilinde 3 ipucu yok")
        # İpucunda yerin adı geçmesin (ör. "Adana kebabı").
        names = set(names)
        for lang in LANGS:
            for i, text in enumerate(h.get(lang, [])):
                t = norm(text)
                for n in names:
                    if len(n) >= 4 and norm(n) in t and lang not in ALLOW.get((key, n), []):
                        errors.append(f"{kind} {key}: {lang}[{i}] adı içeriyor ({n}): {text}")
    for key in hints:
        if key not in places:
            errors.append(f"{kind} {key}: bilinmeyen yer")
    return errors


def main():
    provinces = json.load(open(os.path.join(RES, "provinces.json"), encoding="utf-8"))["provinces"]
    world = json.load(open(os.path.join(RES, "world.json"), encoding="utf-8"))["countries"]
    p_names = {str(p["id"]): [p["name"]] for p in provinces}
    c_names = {c["code"]: [c["name"], *c.get("names", {}).values()] for c in world}

    p_hints = load("provinces_*.json")
    c_hints = load("countries_*.json")
    errors = check("il", p_hints, p_names) + check("ülke", c_hints, c_names)
    for e in errors:
        print(e)
    if errors:
        sys.exit(f"{len(errors)} sorun")

    out = {"provinces": p_hints, "countries": c_hints}
    with open(os.path.join(RES, "hints.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(p_hints)} il, {len(c_hints)} ülke için ipucu yazıldı")


if __name__ == "__main__":
    main()
