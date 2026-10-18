#!/usr/bin/env python3
"""Ülke adlarının İngilizce, Almanca, Fransızca, İspanyolca ve İtalyanca karşılıkları.

build_world.py bu modülü kullanır. Doğrudan çalıştırılırsa mevcut world.json'a yalnızca
"names" alanını ekler; geometri, sıra ve mesafe matrisi değişmez (günlük bulmaca bozulmaz).

Kullanım: python3 tools/country_names.py && cp Atlas/Resources/world.json web/data/
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "ne_50m_countries.geojson")
DST = os.path.join(ROOT, "Atlas", "Resources", "world.json")

LANGS = ["en", "de", "fr", "es", "it"]

# Natural Earth adları yerine kullanılanlar. Kıbrıs adları Türkçedeki tercihle (Güney Kıbrıs / KKTC) aynı.
OVERRIDES = {
    "USA": {"en": "United States", "it": "Stati Uniti"},
    "TUR": {"en": "Türkiye"},
    "CHN": {"en": "China", "de": "China", "fr": "Chine"},
    "TWN": {"de": "Taiwan", "es": "Taiwán"},
    "CYP": {"en": "South Cyprus", "de": "Südzypern", "fr": "Chypre du Sud", "es": "Chipre del Sur", "it": "Cipro del Sud"},
    "CYN": {"en": "Northern Cyprus", "de": "Nordzypern", "fr": "Chypre du Nord", "es": "Chipre del Norte", "it": "Cipro del Nord"},
    "BHS": {"en": "Bahamas"},
    "GMB": {"en": "Gambia"},
    "FSM": {"en": "Micronesia", "de": "Mikronesien", "fr": "Micronésie", "es": "Micronesia", "it": "Micronesia"},
    "MCO": {"it": "Monaco"},
    "SWZ": {"es": "Esuatini", "it": "Eswatini"},
    "VNM": {"fr": "Vietnam"},
    "MDA": {"de": "Moldau"},
    "PSX": {"es": "Palestina"},
}

# Aramada ayrıca kabul edilen yaygın adlar.
EXTRA_ALIASES = {
    "TUR": ["Turkey", "Turkiye"],
    "USA": ["USA", "US", "America", "Amerika", "États-Unis d'Amérique", "EE. UU.", "EEUU", "Stati Uniti d'America", "Vereinigte Staaten von Amerika"],
    "GBR": ["England", "Great Britain", "Britain", "Großbritannien", "Grande-Bretagne", "Angleterre", "Inglaterra", "Gran Bretaña", "Inghilterra", "Gran Bretagna"],
    "CYP": ["Cyprus", "Zypern", "Chypre", "Chipre", "Cipro", "Republic of Cyprus", "Republik Zypern"],
    "CYN": ["TRNC", "Turkish Republic of Northern Cyprus", "Türkische Republik Nordzypern", "République turque de Chypre du Nord", "República Turca del Norte de Chipre", "Repubblica Turca di Cipro del Nord"],
    "CZE": ["Czechia", "Tschechische Republik", "République tchèque", "Chequia", "Cechia"],
    "NLD": ["Holland", "Holanda", "Olanda"],
    "CIV": ["Côte d'Ivoire", "Costa d'Avorio"],
    "MMR": ["Burma", "Birma"],
    "SWZ": ["Swaziland", "Swasiland", "Suazilandia", "Swaziland"],
    "TLS": ["Timor-Leste", "Osttimor"],
    "CPV": ["Cabo Verde"],
    "COD": ["DR Congo", "DRC", "Congo-Kinshasa", "RDC", "RD Congo", "Kongo-Kinshasa"],
    "COG": ["Congo", "Congo-Brazzaville", "Kongo", "Kongo-Brazzaville"],
    "MKD": ["Macedonia", "Mazedonien", "Macédoine"],
    "TWN": ["Republic of China", "Republik China", "República de China"],
    "CHN": ["People's Republic of China", "Volksrepublik China", "République populaire de Chine"],
    "VAT": ["Vatican", "Vatikan", "Vaticano", "Holy See"],
    "KOR": ["Korea"], "PRK": ["DPRK"],
    "BLR": ["Weißrussland", "Byelorussia"],
    "MDA": ["Moldawien", "Republik Moldau"],
    "ARE": ["UAE", "VAE", "EAU", "Emirates"],
}


def localized_names(code, props):
    """{"en": ..., "de": ..., ...}"""
    names = {lang: props[f"NAME_{lang.upper()}"] for lang in LANGS}
    names.update(OVERRIDES.get(code, {}))
    return names


def aliases(code):
    return EXTRA_ALIASES.get(code, [])


def main():
    src = json.load(open(SRC, encoding="utf-8"))
    by_code = {}
    for f in src["features"]:
        by_code.setdefault(f["properties"]["ADM0_A3"], f["properties"])
    world = json.load(open(DST, encoding="utf-8"))
    for c in world["countries"]:
        names = localized_names(c["code"], by_code[c["code"]])
        c["names"] = names
        extra = set(c["aliases"]) | set(aliases(c["code"]))
        extra -= set(names.values()) | {c["name"]}
        c["aliases"] = sorted(a for a in extra if a)
    with open(DST, "w", encoding="utf-8") as fh:
        json.dump(world, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(world['countries'])} ülkeye {len(LANGS)} dilde ad eklendi")


if __name__ == "__main__":
    main()
