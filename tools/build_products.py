"""
Construit la base de produits embarquée (lite/data/products-fr.tsv) à partir de
l'export complet d'Open Food Facts (licence ODbL), lu en flux sans l'enregistrer.

Garde les produits vendus en France, avec un nom, triés par nombre de scans
(les plus courants d'abord), limités à MAX_PRODUCTS.

Format de sortie (une ligne par produit, séparateur tabulation) :
    code  nom  marque  n°catégorie  contenance  image  kcal/100g (ou vide)
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
# Copie locale avec les étiquettes de catégorie (non publiée, voir .gitignore) :
# « python tools/build_products.py --offline » recalcule les catégories en quelques secondes.
RAW = os.path.join(os.path.dirname(__file__), "cache", "products-fr-raw.tsv")

# Étiquettes trop générales, ignorées (« plant-based-foods-and-BEVERAGES »
# classait des pâtes ou du riz dans Boissons). Mêmes règles que lite/logic.js.
IGNORED = {"en:plant-based-foods-and-beverages", "en:plant-based-foods",
           "en:beverages-and-beverages-preparations"}
FROZEN = ["frozen"]
DRINKS = ["beverages", "drinks", "waters", "juices", "sodas", "wines", "beers", "ciders",
          "spirits", "alcoholic", "nectars", "plant-milks"]
CANNED = ["canned"]
FRESH = ["dairies", "dairy", "yogurts", "cheeses", "meats", "fresh", "eggs", "fishes",
         "butters", "creams", "hams", "sausages", "refrigerated", "chilled", "charcuteries",
         "poultries", "seafood", "fermented-milk"]


def category_index(tags):
    # aussi « fruit-based-foods-and-beverages », « vegetable-based-foods-and-beverages »…
    tags = [t for t in tags if t not in IGNORED and "foods-and-beverages" not in t]

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
        need = ["code", "product_name", "brands", "categories_tags", "countries_tags", "quantity", "unique_scans_n",
                "energy-kcal_100g"]
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
            kcal = ""
            try:
                k = float(row[col["energy-kcal_100g"]] or "nan")
                if 0 <= k <= 950:
                    kcal = str(int(round(k)))
            except ValueError:
                pass
            raw = (code, name, clean(row[col["brands"]].split(",")[0], 40), ",".join(tags),
                   clean(row[col["quantity"]], 20), img, kcal)
            kept += 1
            item = (scans, code, raw)
            if len(heap) < MAX_PRODUCTS:
                heapq.heappush(heap, item)
            elif item > heap[0]:
                heapq.heapreplace(heap, item)
    raws = [raw for _, _, raw in sorted(heap, key=lambda x: x[1])]
    os.makedirs(os.path.dirname(RAW), exist_ok=True)
    with open(RAW, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join("\t".join(r) for r in raws) + "\n")
    print("%d produits lus, %d vendus en France" % (seen, kept))
    write_output(raws)


def write_output(raws):
    """Écrit la base publiée : code, nom, marque, n° catégorie, contenance, image, kcal."""
    lines = []
    for code, name, brand, tags, qty, img, kcal in raws:
        cat = category_index([t for t in tags.split(",") if t])
        lines.append("\t".join([code, name, brand, str(cat), qty, img, kcal]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("Terminé : %d produits, %.1f Mo -> %s" % (len(lines), os.path.getsize(OUT) / 1e6, os.path.abspath(OUT)))


def offline():
    """Recalcule les catégories depuis la copie locale, sans retélécharger."""
    with open(RAW, encoding="utf-8") as f:
        raws = [tuple(line.rstrip("\n").split("\t")) for line in f if line.strip()]
    write_output(raws)


if __name__ == "__main__":
    if "--offline" in sys.argv:
        offline()
    else:
        main()
