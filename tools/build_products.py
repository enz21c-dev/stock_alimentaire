"""
Construit la base de produits embarquée (lite/data/products-fr.tsv) à partir de
l'export complet d'Open Food Facts (licence ODbL), lu en flux sans l'enregistrer.

Garde les produits vendus en France, avec un nom, triés par nombre de scans
(les plus courants d'abord), limités à MAX_PRODUCTS.

Format de sortie (une ligne par produit, séparateur tabulation) :
    code  nom  marque  n°catégorie  contenance  image
n°catégorie : 0 Frais, 1 Surgelé, 2 Épicerie, 3 Conserves, 4 Boissons, 5 Autre
image : fin de l'URL de la photo (ex. front_fr.633.200.jpg), le début se
        reconstruit à partir du code-barres.

Utilisation :  python tools/build_products.py   (dure 10 à 30 minutes)
"""
import csv
import gzip
import heapq
import io
import os
import re
import sys
import urllib.request

URL = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
MAX_PRODUCTS = int(os.environ.get("MAX_PRODUCTS", "60000"))
OUT = os.path.join(os.path.dirname(__file__), "..", "lite", "data", "products-fr.tsv")

FROZEN = ["frozen"]
DRINKS = ["beverages", "drinks", "waters", "juices", "sodas", "wines", "beers"]
CANNED = ["canned"]
FRESH = ["dairies", "dairy", "yogurts", "cheeses", "meats", "fresh", "eggs", "fishes",
         "butters", "creams", "hams", "sausages", "refrigerated"]


def category_index(tags):
    def has(keys):
        return any(k in t for t in tags for k in keys)
    if has(FROZEN):
        return 1
    if has(DRINKS):
        return 4
    if has(CANNED):
        return 3
    if has(FRESH):
        return 0
    if not tags:
        return 5
    return 2


def clean(s, n=80):
    return re.sub(r"\s+", " ", (s or "")).strip()[:n]


def main():
    csv.field_size_limit(1 << 30)
    req = urllib.request.Request(URL, headers={"User-Agent": "StockAlimentaire/1.0 (application personnelle)"})
    heap = []  # (scans, code, ligne) — garde les MAX_PRODUCTS plus scannés
    seen = 0
    kept = 0
    with urllib.request.urlopen(req, timeout=120) as resp:
        text = io.TextIOWrapper(gzip.GzipFile(fileobj=resp), encoding="utf-8", errors="replace", newline="")
        reader = csv.reader(text, delimiter="\t", quoting=csv.QUOTE_NONE)
        header = next(reader)
        col = {name: i for i, name in enumerate(header)}
        need = ["code", "product_name", "brands", "categories_tags", "countries_tags", "quantity", "unique_scans_n"]
        missing = [c for c in need if c not in col]
        if missing:
            sys.exit("Colonnes absentes de l'export : %s" % missing)
        img_col = col.get("image_small_url")
        name_fr_col = col.get("product_name_fr")
        width = len(header)
        for row in reader:
            seen += 1
            if seen % 500000 == 0:
                print("  %d produits lus, %d gardés" % (seen, len(heap)), flush=True)
            if len(row) < width:
                continue
            if "en:france" not in row[col["countries_tags"]]:
                continue
            code = row[col["code"]].strip()
            if not code.isdigit() or not (8 <= len(code) <= 14):
                continue
            name = clean(row[name_fr_col]) if name_fr_col is not None else ""
            name = name or clean(row[col["product_name"]])
            if not name:
                continue
            try:
                scans = int(float(row[col["unique_scans_n"]] or 0))
            except ValueError:
                scans = 0
            tags = [t for t in row[col["categories_tags"]].split(",") if t]
            img = ""
            if img_col is not None:
                u = row[img_col]
                if u.startswith("https://images.openfoodfacts.org/images/products/"):
                    img = u.rsplit("/", 1)[-1]
            line = "\t".join([
                code, name, clean(row[col["brands"]].split(",")[0], 40),
                str(category_index(tags)), clean(row[col["quantity"]], 20), img,
            ])
            kept += 1
            item = (scans, code, line)
            if len(heap) < MAX_PRODUCTS:
                heapq.heappush(heap, item)
            elif item > heap[0]:
                heapq.heapreplace(heap, item)
    lines = [line for _, _, line in sorted(heap, key=lambda x: x[1])]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    size = os.path.getsize(OUT)
    print("Terminé : %d produits lus, %d vendus en France, %d gardés, %.1f Mo -> %s"
          % (seen, kept, len(lines), size / 1e6, os.path.abspath(OUT)))


if __name__ == "__main__":
    main()
