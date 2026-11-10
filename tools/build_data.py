#!/usr/bin/env python3
"""Türkiye il sınırlarından uygulamanın kullandığı provinces.json'u üretir.

- Kaynak: geoBoundaries TUR ADM1 (gbOpen, CC BY 4.0), il başına ~4.500 nokta. Eski kaynak
  (cihadturhan/tr-geojson) çok kabaydı: Zonguldak 22 noktaydı, Bolu ile arasında 15 km boşluk
  kalıyordu ve komşu olmayan iller (Bursa–Sakarya) komşu görünüyordu.
- Sınırlar ortak kenarları koruyarak sadeleştirilir (çizim sade, mesafeler isabetli geometriden) (`shapely.coverage_simplify`): iki il aynı
  çizgiyi paylaşır, aralarında boşluk ya da üst üste binme olmaz.
- Her il çifti için en yakın sınırlar arası mesafe (km) önceden hesaplanır; komşular 0 km.
- Plaka kodu ISO 3166-2 kodundan (TR-06 → 6) alınır; il sırası (dolayısıyla günlük bulmaca) değişmez.

Gerekenler: shapely >= 2.1 (python3 -m pip install shapely).
Kaynak dosya yoksa indirilir (tools/cache/, git'e girmez).
Kullanım: python3 tools/build_data.py
"""
import json
import math
import os
import urllib.request

import shapely
from shapely.geometry import shape
from shapely.ops import nearest_points

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", "cache")
SRC = os.path.join(CACHE, "geoBoundaries-TUR-ADM1.geojson")
SRC_URL = ("https://github.com/wmgeolab/geoBoundaries/raw/main/releaseData/gbOpen/TUR/ADM1/"
           "geoBoundaries-TUR-ADM1.geojson")
DST = os.path.join(ROOT, "Atlas", "Resources", "provinces.json")

PLATES = [
    "Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Amasya", "Ankara", "Antalya", "Artvin",
    "Aydın", "Balıkesir", "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale",
    "Çankırı", "Çorum", "Denizli", "Diyarbakır", "Edirne", "Elazığ", "Erzincan", "Erzurum",
    "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane", "Hakkari", "Hatay", "Isparta", "Mersin",
    "İstanbul", "İzmir", "Kars", "Kastamonu", "Kayseri", "Kırklareli", "Kırşehir", "Kocaeli",
    "Konya", "Kütahya", "Malatya", "Manisa", "Kahramanmaraş", "Mardin", "Muğla", "Muş",
    "Nevşehir", "Niğde", "Ordu", "Rize", "Sakarya", "Samsun", "Siirt", "Sinop", "Sivas",
    "Tekirdağ", "Tokat", "Trabzon", "Tunceli", "Şanlıurfa", "Uşak", "Van", "Yozgat", "Zonguldak",
    "Aksaray", "Bayburt", "Karaman", "Kırıkkale", "Batman", "Şırnak", "Bartın", "Ardahan",
    "Iğdır", "Yalova", "Karabük", "Kilis", "Osmaniye", "Düzce",
]

# Çizim için sadeleştirme toleransı (derece; ~8 km). Daha küçüğü (0,005–0,03) sınırları gerçeğe yakın ama
# çok kıvrımlı çiziyordu; kullanıcı göz yorduğunu söyledi, atlaslardaki gibi sade çizgiler istendi.
DRAW_TOLERANCE = 0.08
# Mesafeler daha isabetli, az sadeleştirilmiş sınırlardan hesaplanır (~500 m).
DIST_TOLERANCE = 0.005
# Bundan küçük adalar (km²) çizilmez.
MIN_ISLAND_KM2 = 2.0
# Ortak kenarlar birebir aynı olduğundan komşular arası mesafe 0'dır; yuvarlama payı.
NEIGHBOR_KM = 0.5
R = 6371.0


def haversine(a, b):
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


# Mesafe aramaları için Türkiye'nin ortasında (39°K) eşit uzaklıklı yaklaşık düzlem (km).
KX = 111.32 * math.cos(math.radians(39))
KY = 110.57


def project(g):
    return shapely.transform(g, lambda c: c * [KX, KY])


def unproject(p):
    return (p.x / KX, p.y / KY)


def polygons(g):
    """Geometrideki tüm çokgenler (Polygon, MultiPolygon ya da karışık koleksiyon)."""
    if g.geom_type == "Polygon":
        return [g]
    return [p for part in getattr(g, "geoms", []) for p in polygons(part)]


def main():
    if not os.path.exists(SRC):
        os.makedirs(CACHE, exist_ok=True)
        print("indiriliyor:", SRC_URL)
        urllib.request.urlretrieve(SRC_URL, SRC)
    src = json.load(open(SRC, encoding="utf-8"))

    ids, geoms = [], []
    for f in src["features"]:
        ids.append(int(f["properties"]["shapeISO"].split("-")[1]))
        g = shapely.make_valid(shape(f["geometry"]))
        geoms.append(shapely.MultiPolygon(polygons(g)))
    assert sorted(ids) == list(range(1, 82)), "81 il bekleniyordu"
    assert shapely.coverage_is_valid(geoms), "il sınırları üst üste biniyor"

    by_id = dict(zip(ids, shapely.coverage_simplify(geoms, DRAW_TOLERANCE)))
    accurate = dict(zip(ids, shapely.coverage_simplify(geoms, DIST_TOLERANCE)))

    provinces = []
    shapes = []
    for pid in range(1, 82):
        g = by_id[pid]
        rings = []
        kept = []
        for p in sorted(polygons(g), key=lambda p: -p.area):
            km2 = project(p).area
            if km2 < MIN_ISLAND_KM2 and rings:
                continue
            # Sadece dış halkalar: il sınırları için delikler önemsiz.
            rings.append([[round(x, 4), round(y, 4)] for x, y in p.exterior.coords])
            kept.append(p)
        shape_kept = shapely.MultiPolygon(kept)
        shapes.append(project(accurate[pid]))
        c = shape_kept.representative_point()
        provinces.append({"id": pid, "name": PLATES[pid - 1], "rings": rings,
                          "center": [round(c.x, 4), round(c.y, 4)]})

    n = len(provinces)
    dist = [[0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            if shapes[i].distance(shapes[j]) < NEIGHBOR_KM:
                km = 0
            else:
                a, b = nearest_points(shapes[i], shapes[j])
                km = int(round(haversine(unproject(a), unproject(b))))
            dist[i][j] = dist[j][i] = km

    out = {"provinces": provinces, "distances": dist}
    with open(DST, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))

    neighbors = {provinces[i]["name"]: [provinces[j]["name"] for j in range(n) if j != i and dist[i][j] == 0] for i in range(n)}
    print("yazıldı:", DST, "·", sum(len(r) for p in provinces for r in p["rings"]), "nokta")
    print("komşu çifti:", sum(len(v) for v in neighbors.values()) // 2)
    for k in ("Ankara", "İstanbul", "Bolu", "Zonguldak", "Kilis"):
        print(k, "komşular:", neighbors[k])
    print("Edirne-Hakkari:", dist[21][29], "km")


if __name__ == "__main__":
    main()
