#!/usr/bin/env python3
"""ne_50m_countries.geojson dosyasından uygulamanın kullandığı world.json'u üretir.

- Oynanabilir ülkeleri seçer, Türkçe adları ve arama için takma adları ekler.
- Kıtalara ayırır (bazı ülkeler iki kıtadadır).
- Geometriyi sadeleştirir (Douglas–Peucker) ve küçük adacıkları atar.
- Oyunda yer almayan bölgeleri (bağımlı topraklar vb.) yalnızca arka plan olarak yazar.

Ülke çiftleri arası sınır mesafeleri ardından tools/compute_distances.swift ile eklenir.

Kaynak: Natural Earth 1:50m Admin 0 – Countries (kamu malı)
Kullanım: python3 tools/build_world.py && swiftc -O tools/compute_distances.swift -o /tmp/cd && /tmp/cd
"""
import json
import math
import os
from collections import Counter

from country_names import aliases as extra_aliases, localized_names

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "ne_50m_countries.geojson")
DST = os.path.join(ROOT, "Atlas", "Resources", "world.json")

TOLERANCE = 0.02  # derece; Douglas–Peucker sadeleştirme eşiği

# Egemen ülke olarak işaretlenmese de oyuna dahil edilenler.
EXTRA_PLAYABLE = {"KOS", "PSX", "TWN", "SAH", "GRL", "CYN", "USA", "GBR", "NZL", "NLD", "FRA", "FIN", "DNK", "CHN", "AUS", "KAZ", "CUB", "ISR"}
# Bir başka ülkenin parçası olarak birleştirilenler.
MERGE = {"SOL": "SOM"}

CONTINENTS = {
    "Europe": "europe", "Asia": "asia", "Africa": "africa", "North America": "northAmerica",
    "South America": "southAmerica", "Oceania": "oceania",
}
CONTINENT_OVERRIDES = {
    "SYC": ["africa"], "MUS": ["africa"], "MDV": ["asia"],
    "TUR": ["europe", "asia"], "RUS": ["europe", "asia"],
    "CYP": ["europe", "asia"], "CYN": ["europe", "asia"],
}

NAME_OVERRIDES = {
    "CHN": "Çin", "TWN": "Tayvan", "CYP": "Güney Kıbrıs", "CZE": "Çekya",
    "SAH": "Batı Sahra", "PSX": "Filistin",
}
ALIASES = {
    "USA": ["ABD", "Amerika", "Birleşik Devletler"], "GBR": ["İngiltere", "UK", "Britanya"],
    "CHN": ["Çin Halk Cumhuriyeti"], "TWN": ["Çin Cumhuriyeti"],
    "CYP": ["Kıbrıs", "Kıbrıs Cumhuriyeti", "GKRY", "Güney Kıbrıs Rum Yönetimi"],
    "CYN": ["KKTC", "Kuzey Kıbrıs"], "CZE": ["Çek Cumhuriyeti"],
    "ZAF": ["Güney Afrika"], "COD": ["Kongo DC", "DKC", "Zaire"], "COG": ["Kongo"],
    "ARE": ["BAE", "Emirlikler"], "SWZ": ["Svaziland"], "MMR": ["Burma"],
    "CPV": ["Cabo Verde", "Cape Verde"], "CIV": ["Côte d'Ivoire"], "KOR": ["Kore"],
    "BIH": ["Bosna"], "MKD": ["Makedonya"], "TLS": ["Timor"], "BLR": ["Belarus"],
    "GNQ": ["Ekvatoral Gine"], "PNG": ["Papua"], "SAU": ["Suudi"], "BHS": ["Bahama"],
    "PHL": ["Filipin"], "NLD": ["Holland"],
}


def perp_dist(p, a, b):
    (x, y), (x1, y1), (x2, y2) = p, a, b
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(x - x1, y - y1)
    t = max(0, min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (x1 + t * dx), y - (y1 + t * dy))


def simplify(points, tol):
    if len(points) < 4:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        s, e = stack.pop()
        best, idx = 0, -1
        for i in range(s + 1, e):
            d = perp_dist(points[i], points[s], points[e])
            if d > best:
                best, idx = d, i
        if best > tol and idx > 0:
            keep[idx] = True
            stack += [(s, idx), (idx, e)]
    return [p for p, k in zip(points, keep) if k]


def ring_size(ring):
    xs, ys = [p[0] for p in ring], [p[1] for p in ring]
    return max(max(xs) - min(xs), max(ys) - min(ys))


def process_rings(polys):
    rings = sorted((poly[0] for poly in polys), key=ring_size, reverse=True)  # yalnızca dış halkalar
    out = []
    for i, ring in enumerate(rings):
        # Küçük adacıkları at; ama küçük ada ülkeleri için en büyük birkaç halkayı her zaman tut.
        if i >= 5 and ring_size(ring) < 0.25:
            continue
        s = simplify(ring, TOLERANCE)
        if len(s) < 4:
            s = ring
        out.append([[round(x, 3), round(y, 3)] for x, y in s])
    return out


def main():
    src = json.load(open(SRC, encoding="utf-8"))
    by_code = {}
    background = []
    for f in src["features"]:
        q = f["properties"]
        code = q["ADM0_A3"]
        g = f["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        if code in MERGE:
            by_code.setdefault(MERGE[code], {"extra": []})["extra"] += polys
            continue
        if not (q["TYPE"] == "Sovereign country" or code in EXTRA_PLAYABLE):
            if code != "ATA":
                background.append(process_rings(polys))
            continue
        entry = by_code.setdefault(code, {"extra": []})
        name = NAME_OVERRIDES.get(code, q["NAME_TR"])
        names = localized_names(code, q)
        aliases = {q["NAME"], q["NAME_EN"], q["NAME_LONG"], q["ADMIN"], q["NAME_TR"], *ALIASES.get(code, []), *extra_aliases(code)}
        aliases -= {name, *names.values()}
        entry.update(
            code=code, name=name, names=names, aliases=sorted(a for a in aliases if a),
            continents=CONTINENT_OVERRIDES.get(code) or [CONTINENTS[q["CONTINENT"]]], polys=polys,
        )

    countries = []
    for code, e in by_code.items():
        countries.append({
            "code": code, "name": e["name"], "names": e["names"], "aliases": e["aliases"], "continents": e["continents"],
            "rings": process_rings(e["polys"] + e["extra"]),
        })
    countries.sort(key=lambda c: c["name"])
    for i, c in enumerate(countries):
        c["id"] = i + 1

    with open(DST, "w", encoding="utf-8") as fh:
        json.dump({"countries": countries, "background": background, "distances": []}, fh, ensure_ascii=False, separators=(",", ":"))

    pts = sum(len(r) for c in countries for r in c["rings"])
    print(f"{len(countries)} ülke, {pts} nokta, {len(background)} arka plan bölgesi")
    print(dict(Counter(k for c in countries for k in c["continents"])))


if __name__ == "__main__":
    main()
