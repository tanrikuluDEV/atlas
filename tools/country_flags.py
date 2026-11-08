"""world.json'daki her ülkeye iki harfli ISO kodunu (`iso2`) ekler; bayrak emojisi bundan üretilir.

Natural Earth'te bazı ülkelerin ISO_A2 alanı -99 olduğu için ISO_A2_EH kullanılır.
KKTC'nin ISO kodu ve bayrak emojisi yok; uygulamalar onun bayrağını kendileri çizer (`iso2` = "CY-N").
Kullanım: python3 tools/country_flags.py && cp Atlas/Resources/world.json web/data/
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORLD = ROOT / "Atlas/Resources/world.json"
geo = json.loads((ROOT / "tools/ne_50m_countries.geojson").read_text())

codes = {}
for f in geo["features"]:
    p = f["properties"]
    codes.setdefault(p["ADM0_A3"], p.get("ISO_A2_EH") or p.get("ISO_A2"))
codes["CYN"] = "CY-N"

world = json.loads(WORLD.read_text())
missing = []
for c in world["countries"]:
    iso = codes.get(c["code"])
    if not iso or iso == "-99":
        missing.append(c["code"])
        continue
    c["iso2"] = iso
if missing:
    raise SystemExit(f"ISO kodu bulunamadı: {missing}")
# build_world.py ile aynı biçimde yaz (sıkıştırılmış).
WORLD.write_text(json.dumps(world, ensure_ascii=False, separators=(",", ":")))
print(f"{len(world['countries'])} ülkeye iso2 eklendi")
