#!/usr/bin/env python3
"""tr-cities.geojson dosyasından uygulamanın kullandığı provinces.json'u üretir.

- İl adlarını düzeltir, plaka kodlarını ekler.
- Her il çifti için en yakın sınırlar arası mesafeyi (km) önceden hesaplar.
  Komşu iller 0 km olarak kaydedilir.

Kaynak: https://github.com/cihadturhan/tr-geojson
Kullanım: python3 tools/build_data.py
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "tr-cities.geojson")
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
RENAMES = {"Afyon": "Afyonkarahisar"}

# Bu mesafenin altındaki sınırlar "komşu" (0 km) sayılır; veri setindeki küçük kaymaları tolere eder.
NEIGHBOR_KM = 2.0
R = 6371.0


def haversine(a, b):
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))


def main():
    src = json.load(open(SRC, encoding="utf-8"))
    provinces = []
    for f in src["features"]:
        name = RENAMES.get(f["properties"]["name"], f["properties"]["name"])
        geom = f["geometry"]
        polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
        # Sadece dış halkalar: il sınırları için delikler önemsiz.
        rings = [[[round(x, 4), round(y, 4)] for x, y in poly[0]] for poly in polys]
        provinces.append({"id": PLATES.index(name) + 1, "name": name, "rings": rings})

    provinces.sort(key=lambda p: p["id"])
    assert [p["id"] for p in provinces] == list(range(1, 82))

    pts = [[pt for ring in p["rings"] for pt in ring] for p in provinces]
    bbox = [(min(x for x, _ in ps), min(y for _, y in ps), max(x for x, _ in ps), max(y for _, y in ps)) for ps in pts]

    n = len(provinces)
    dist = [[0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1, n):
            # Çok uzak çiftlerde tüm noktaları dolaşmamak için önce kaba bir alt sınır bulunur.
            best = math.inf
            for a in pts[i][::4]:
                for b in pts[j][::4]:
                    d = (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2
                    if d < best:
                        best, ba, bb = d, a, b
            # Ardından en yakın bölgenin çevresinde tam çözünürlükte arama.
            coarse = haversine(ba, bb)
            margin = coarse / 80.0 + 0.1  # derece cinsinden cömert pencere
            ca = [a for a in pts[i] if abs(a[0] - bb[0]) < margin * 2 + 0.3 and abs(a[1] - bb[1]) < margin * 2 + 0.3]
            cb = [b for b in pts[j] if abs(b[0] - ba[0]) < margin * 2 + 0.3 and abs(b[1] - ba[1]) < margin * 2 + 0.3]
            km = min((haversine(a, b) for a in ca for b in cb), default=coarse)
            km = min(km, coarse)
            km = 0 if km < NEIGHBOR_KM else int(round(km))
            dist[i][j] = dist[j][i] = km

    for p in provinces:
        ps = [pt for ring in p["rings"] for pt in ring]
        p["center"] = [round(sum(x for x, _ in ps) / len(ps), 4), round(sum(y for _, y in ps) / len(ps), 4)]

    out = {"provinces": provinces, "distances": dist}
    with open(DST, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))

    neighbors = {provinces[i]["name"]: [provinces[j]["name"] for j in range(n) if j != i and dist[i][j] == 0] for i in range(n)}
    print("yazıldı:", DST)
    for k in ("Ankara", "İstanbul", "Yalova", "Kilis", "Konya"):
        print(k, "komşular:", neighbors[k])
    print("Edirne-Hakkari:", dist[21][29], "km")


if __name__ == "__main__":
    main()
