# Stock Alimentaire

Appli de gestion du stock alimentaire du foyer.

**Adresse : https://enz21c-dev.github.io/stock_alimentaire/**

## Deux versions dans ce dÃ©pÃ´t

| Dossier | Version | UtilisÃ©e pour |
|---|---|---|
| `lite/` | **Version lÃ©gÃ¨re** en HTML/JavaScript simple, compatible **Safari d'iOS 12** | **C'est celle qui est publiÃ©e** (l'iPad de la maison est bloquÃ© en iOS 12.5.8, trop ancien pour Flutter) |
| `lib/`, `web/`, `test/` | Version **Flutter** (Dart) | GardÃ©e pour un futur appareil rÃ©cent ou une appli Android |

### Version lÃ©gÃ¨re (`lite/`)

- `index.html`, `style.css` : la page ; `logic.js` : rÃ¨gles (lots, FEFO, besoins des
  recettes, liste de courses) ; `app.js` : Ã©crans et enregistrement.
- DonnÃ©es dans le `localStorage` de Safari, sur l'iPad uniquement.
- Scan : bibliothÃ¨que ZXing (`vendor/`, licence Apache 2.0) + Open Food Facts.
- Sur iOS 12 la camÃ©ra ne marche que **dans Safari** (pas en mode plein Ã©cran), d'oÃ¹
  l'absence volontaire de `apple-mobile-web-app-capable`.
- RÃ¨gles de compatibilitÃ© Safari 12 : pas de `?.`, `??`, `replaceAll`, `<dialog>`,
  ni de `gap` en flexbox.
- Tests : `node --test lite/test/logic.test.js` ; essai local :
  `python -m http.server 8081 --directory lite` puis http://localhost:8081.
- Publication automatique (`.github/workflows/deploy.yml`) Ã  chaque `git push`.

## Version Flutter

Ã‰crite en **Flutter** comme **appli web**. Pas de serveur, pas de compte : les donnÃ©es
restent dans le navigateur de l'appareil (IndexedDB). Seul appel rÃ©seau : Open Food Facts au scan.

## Pourquoi une appli web et pas une appli iOS / Android ?

La tablette cible est un iPad. Une vraie appli iOS demande un Mac pour compiler et
une signature Apple (rÃ©installation tous les 7 jours avec un compte gratuit, ou
99 â‚¬/an). L'appli web Ã©vite tout Ã§a : mÃªme code Flutter, installation via Safari.
Contreparties : pas de notifications en arriÃ¨re-plan (remplacÃ©es par l'onglet
Â« BientÃ´t pÃ©rimÃ©s Â», un bandeau d'alerte et un badge Ã  l'ouverture), et il faut
exporter une sauvegarde de temps en temps.

Le mÃªme code pourra plus tard Ãªtre compilÃ© en appli Android (`flutter create
--platforms=android .`) ou iOS : il faudra alors ajouter une base locale native
(sembast fonctionne aussi hors web) et les notifications.

## FonctionnalitÃ©s

- **Stock par lots** : un produit peut avoir plusieurs lots, chacun avec sa quantitÃ©
  et sa date. Affichage groupÃ© (Â« Yaourts â€” 4 au total Â· 2 lots Â»), consommation
  FEFO (le lot qui pÃ©rime le plus tÃ´t part en premier), bouton Â« Annuler Â».
- **Scan en rafale** (camÃ©ra arriÃ¨re) + Open Food Facts (nom, marque, photo,
  catÃ©gorie). Produit inconnu ou pas de camÃ©ra â†’ saisie manuelle / code tapÃ© Ã  la main.
- QuantitÃ©s en piÃ¨ce, g, kg, ml, L (conversions automatiques).
- Recherche, filtre par catÃ©gorie, tri par date ou par nom.
- **PÃ©remption** : pastille verte / orange / rouge, onglet Â« BientÃ´t pÃ©rimÃ©s Â»,
  dÃ©lai d'alerte rÃ©glable (3 jours par dÃ©faut).
- **Recettes** (ingrÃ©dients reliÃ©s au stock ou en texte libre, photo, prÃ©paration).
- **Planning** : par jour ou liste libre ; comparaison automatique avec le stock.
- **Liste de courses** gÃ©nÃ©rÃ©e automatiquement (quantitÃ©s cumulÃ©es), cases Ã  cocher,
  ajout manuel.
- Recette faite â†’ l'appli **propose** de retirer les ingrÃ©dients du stock (jamais
  sans confirmation), avec annulation possible.
- **RÃ©glages** : dÃ©lai d'alerte, catÃ©gories, export / import JSON.

## Organisation du code

```
lib/
  main.dart                  dÃ©marrage, thÃ¨me vert Material 3, mode sombre auto
  models/models.dart         Product, Batch, Recipe, RecipeIngredient, MealPlanEntry,
                             ShoppingItem, Settings
  logic/units.dart           unitÃ©s, conversions, formatage Â« Ã  la franÃ§aise Â»
  logic/stock_logic.dart     jours restants, FEFO, besoins des recettes, liste de courses
  data/app_state.dart        donnÃ©es en mÃ©moire + enregistrement (sembast), export/import
  data/db_factory_*.dart     IndexedDB dans le navigateur, mÃ©moire ailleurs (tests)
  services/open_food_facts.dart
  platform/                  bip de scan, partage/tÃ©lÃ©chargement de fichier (navigateur)
  ui/                        les Ã©crans
test/logic_test.dart         tests de la logique sensible
web/                         page HTML, manifeste, icÃ´nes
```

## Commandes utiles (PowerShell, dans ce dossier)

Flutter est installÃ© dans `C:\src\flutter` (dÃ©jÃ  ajoutÃ© au PATH de l'utilisateur).

| But | Commande |
|---|---|
| Lancer en dÃ©veloppement dans Chrome (rechargement Ã  chaud avec `r`) | `flutter run -d chrome` |
| Lancer les tests | `flutter test` |
| VÃ©rifier le code | `flutter analyze` |
| Construire la version Ã  publier | `flutter build web --release` |

La version construite est dans `build\web`. Pour la tester sur le PC :
`python -m http.server 8080 --directory build\web` puis ouvrir http://localhost:8080.

> La camÃ©ra du navigateur n'est autorisÃ©e qu'en **HTTPS** (ou sur `localhost`).
> Pour scanner depuis l'iPad, l'appli doit donc Ãªtre publiÃ©e sur un hÃ©bergement HTTPS
> (ex. GitHub Pages) : une simple adresse `http://192.168.x.x` du PC ne suffit pas.

## Installer sur l'iPad

1. Ouvrir l'adresse de l'appli publiÃ©e dans **Safari**.
2. Bouton **Partager** â†’ **Sur l'Ã©cran d'accueil**.
3. Lancer l'appli depuis l'icÃ´ne Â« Stock Â», autoriser la camÃ©ra au premier scan.
4. Penser Ã  **exporter une sauvegarde** de temps en temps (RÃ©glages â†’ Exporter).
