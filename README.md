# Stock Alimentaire

Appli de gestion du stock alimentaire du foyer, écrite en **Flutter** et publiée
comme **appli web** pour être utilisée sur un **iPad** (ajoutée à l'écran d'accueil
depuis Safari). Pas de serveur, pas de compte : les données restent dans le
navigateur de l'appareil (IndexedDB). Seul appel réseau : Open Food Facts au scan.

## Pourquoi une appli web et pas une appli iOS / Android ?

La tablette cible est un iPad. Une vraie appli iOS demande un Mac pour compiler et
une signature Apple (réinstallation tous les 7 jours avec un compte gratuit, ou
99 €/an). L'appli web évite tout ça : même code Flutter, installation via Safari.
Contreparties : pas de notifications en arrière-plan (remplacées par l'onglet
« Bientôt périmés », un bandeau d'alerte et un badge à l'ouverture), et il faut
exporter une sauvegarde de temps en temps.

Le même code pourra plus tard être compilé en appli Android (`flutter create
--platforms=android .`) ou iOS : il faudra alors ajouter une base locale native
(sembast fonctionne aussi hors web) et les notifications.

## Fonctionnalités

- **Stock par lots** : un produit peut avoir plusieurs lots, chacun avec sa quantité
  et sa date. Affichage groupé (« Yaourts — 4 au total · 2 lots »), consommation
  FEFO (le lot qui périme le plus tôt part en premier), bouton « Annuler ».
- **Scan en rafale** (caméra arrière) + Open Food Facts (nom, marque, photo,
  catégorie). Produit inconnu ou pas de caméra → saisie manuelle / code tapé à la main.
- Quantités en pièce, g, kg, ml, L (conversions automatiques).
- Recherche, filtre par catégorie, tri par date ou par nom.
- **Péremption** : pastille verte / orange / rouge, onglet « Bientôt périmés »,
  délai d'alerte réglable (3 jours par défaut).
- **Recettes** (ingrédients reliés au stock ou en texte libre, photo, préparation).
- **Planning** : par jour ou liste libre ; comparaison automatique avec le stock.
- **Liste de courses** générée automatiquement (quantités cumulées), cases à cocher,
  ajout manuel.
- Recette faite → l'appli **propose** de retirer les ingrédients du stock (jamais
  sans confirmation), avec annulation possible.
- **Réglages** : délai d'alerte, catégories, export / import JSON.

## Organisation du code

```
lib/
  main.dart                  démarrage, thème vert Material 3, mode sombre auto
  models/models.dart         Product, Batch, Recipe, RecipeIngredient, MealPlanEntry,
                             ShoppingItem, Settings
  logic/units.dart           unités, conversions, formatage « à la française »
  logic/stock_logic.dart     jours restants, FEFO, besoins des recettes, liste de courses
  data/app_state.dart        données en mémoire + enregistrement (sembast), export/import
  data/db_factory_*.dart     IndexedDB dans le navigateur, mémoire ailleurs (tests)
  services/open_food_facts.dart
  platform/                  bip de scan, partage/téléchargement de fichier (navigateur)
  ui/                        les écrans
test/logic_test.dart         tests de la logique sensible
web/                         page HTML, manifeste, icônes
```

## Commandes utiles (PowerShell, dans ce dossier)

Flutter est installé dans `C:\src\flutter` (déjà ajouté au PATH de l'utilisateur).

| But | Commande |
|---|---|
| Lancer en développement dans Chrome (rechargement à chaud avec `r`) | `flutter run -d chrome` |
| Lancer les tests | `flutter test` |
| Vérifier le code | `flutter analyze` |
| Construire la version à publier | `flutter build web --release` |

La version construite est dans `build\web`. Pour la tester sur le PC :
`python -m http.server 8080 --directory build\web` puis ouvrir http://localhost:8080.

> La caméra du navigateur n'est autorisée qu'en **HTTPS** (ou sur `localhost`).
> Pour scanner depuis l'iPad, l'appli doit donc être publiée sur un hébergement HTTPS
> (ex. GitHub Pages) : une simple adresse `http://192.168.x.x` du PC ne suffit pas.

## Installer sur l'iPad

1. Ouvrir l'adresse de l'appli publiée dans **Safari**.
2. Bouton **Partager** → **Sur l'écran d'accueil**.
3. Lancer l'appli depuis l'icône « Stock », autoriser la caméra au premier scan.
4. Penser à **exporter une sauvegarde** de temps en temps (Réglages → Exporter).
