# Compilation de GnuCash en AppImage avec Docker Compose

Ce projet permet de compiler [GnuCash](https://github.com/gnucash/gnucash) et de le packager en AppImage en utilisant Docker Compose.

# 📁 Structure du projet

```
./
├─ Dockerfile                      # Image Docker pour la compilation
├─ docker-compose.yml              # Configuration Docker Compose
├─ build.sh                        # Script d'aide pour simplifier les appels pour les compilations
├─ build-gnucash.sh                # Script principal de compilation et packaging
├─ shell.sh                        # Ouvrir un shell interactif dans le conteneur
├─ diagnose-appimage.sh            # Diagnostic pour les AppImages
├─ release.sh                      # Compiler et pousser une version sur github
├─ .gitignore                      # Fichiers à ignorer par Git
├─ .github/
│  ├─ workflows/
│  |  ├─ GITHUB_ACTIONS.md         # Documentation GitHub Actions
│  |  ├─ build-appimage.yml        # Build CI/CD standard
│  |  ├─ build-release.yml         # Build optimisé pour releases
│  |  ├─ nightly.yml               # Builds quotidiens automatiques
│  |  ├─ check-new-version.yml     # Build avec version upstream
│  │  └─ pr-validation.yml
| -- Répertoires et fichiers créés automatiquement par le build :
├─ build/                          # Répertoire de cache
│  ├─ gnucash-x.xx.tar.bz2         # Archive source
│  ├─ gnucash-x.xx/                # Sources extraites (propres, non modifiées)
│  ├─ gnucash-x.xx_build/          # Répertoire de build séparé (CMake + compilation)
│  ├─ AppDir/                      # Installation temporaire pour AppImage
│  │  └─ usr/local/                # Tout GnuCash est installé ici
│  │     ├─ bin/                   # Binaires, dont l'application "gnucash"
│  │     ├─ lib/                   # Bibliothèques GnuCash et dépenances
│  │     └─ share/                 # Données et ressources
│  ├─ linuxdeploy-x86_64.AppImage  # Outil de packaging
│  └─ appimagetool-x86_64.AppImage # Outil de création d'AppImage
└─ output/                         # Répertoire de sortie
   └─ GnuCash-x.xx-x86_64.AppImage # Fichier AppImage final
```

**Avantages de cette structure :**

- ✅ **Sources propres** : `gnucash-x.xx/` reste intact et non pollué par les fichiers de build
- ✅ **Build séparé** : `gnucash-x.xx`_build/` contient toute la compilation (CMake, Makefiles, objets)
- ✅ **Structure cohérente** : Tout dans `/usr/local` (pas de mélange `/usr` et `/usr/local`)
- ✅ **Cache intelligent** : Les outils AppImage sont téléchargés une seule fois et réutilisés
- ✅ **Scripts modifiables** : Pas besoin de reconstruire l'image Docker pour modifier les scripts
- ✅ **Tout accessible** : Pas de volumes Docker cachés, tout est sur votre système de fichiers
- ✅ **Shell interactif** : Utilisateur `docker` avec droits sudo pour le débogage

### Dockerfile

**Python**

La dernière version de python est prise du PPA "deadsnakes" et définie comme python par défaut en remplacement de celle de la distribution ubuntu.

**Guile et ses dépendances** (runtime) :

```dockerfile
    guile-3.0 \
    guile-3.0-dev \
    guile-3.0-libs \
    libgc1 \
    libgmp10 \
    libunistring2 \
    libffi8 \
```

Explication : `guile-3.0-dev` installe les headers pour la compilation, mais pas forcément toutes les bibliothèques runtime. On ajoute explicitement les packages runtime et leurs dépendances pour les inclure ensuite dans l'AppImage

### Avantages de l'architecture avec volumes

**Modification des scripts sans rebuild :**

- Vous pouvez modifier `build-gnucash.sh` directement
- Pas besoin de reconstruire l'image Docker
- Il suffit de relancer `docker compose up`

**Cache persistant et accessible :**

- Le répertoire `build/` contient tous les fichiers de cache
- Accessible depuis votre système hôte pour inspecter/déboguer
- Pas de volumes Docker cachés

**Workflow de développement rapide :**

```bash
# Modifier build-gnucash.sh avec votre éditeur
nano build-gnucash.sh

# Tester immédiatement
./build.sh build
```

**Shell interactif pour le débogage :** Le conteneur utilise un utilisateur `docker` avec droits sudo sans mot de passe :

```bash
# Ouvrir un shell dans le conteneur
./shell.sh

# Une fois dans le shell, vous avez accès à :
docker@container:/workspace$ ls build/
docker@container:/workspace$ sudo apt install strace
docker@container:/workspace$ cd build/gnucash-x.xx_build
docker@container:/workspace$ make  # Compilation manuelle
```

### Processus de compilation

Le processus automatique (build.sh) va :

1. Construire l'image Docker avec toutes les dépendances (patchelf, cmake, gcc, etc.)
2. Télécharger GnuCash (si pas déjà en cache)
3. Extraire les sources dans `build/gnucash-x.xx/`
4. Compiler dans `build/gnucash-x.xx_build/` (séparé des sources)
5. Installer dans `build/AppDir/`
6. Télécharger linuxdeploy et appimagetool (si pas déjà en cache)
7. Collecter les dépendances avec linuxdeploy
8. Créer l'AppImage avec appimagetool
9. Placer l'AppImage dans `output/GnuCash-x.xx-x86_64.AppImage`

# 📋 Prérequis

#### Pour GitHub Actions

- Repository GitHub (public ou privé)
- GitHub Actions activé (gratuit pour repositories publics)

#### Pour build local

- Docker installé
- Docker Compose installé
- Environ 5-10 GB d'espace disque disponible

# 🎯 Build

### Via GitHub Actions

Voir la documentation complète dans [.github/workflow/GITHUB_ACTIONS.md](.github/workflow/GITHUB_ACTIONS.md)

**Résumé:**

- **Push sur main/develop** → Build automatique
- **Pull Request** → Build de vérification
- **Tag version** → Version de l'application GnuCash compilée
- **Manuel** → Via interface GitHub Actions

**Option 1 - Build manuel:**
Réalisé via l'onglet "Actions" du repository, "Build GnuCash AppImage".
L'artefact est disponible mais pas de release créée.

**Option 2 - Release automatique:**

```bash
git tag -a 5.14 -m "Release GnuCash 5.14"
git push origin v5.14
```

Une release sera créée automatiquement avec l'AppImage.

### Build local

#### Méthode simple (avec script helper)

```bash
chmod +x build.sh

# Compilation normale (rapide, utilise le cache)
./build.sh build

# Recompilation complète (nettoie le cache de build)
./build.sh rebuild

# Nettoyage complet (cache + images Docker + volumes)
./build.sh clean

# Nettoyage approfondi (+ cache Docker buildkit)
./build.sh clean-deep
```

#### Méthode manuelle (docker compose)

```bash
# Compilation normale
docker compose up --build

# Recompilation complète
docker compose down
rm -rf build/gnucash-x.xx_build
docker compose up --build

# Nettoyage total
docker compose down --volumes --rmi all
rm -rf build/ output/
```

#### Pourquoi plusieurs méthodes de build ?

**`./build.sh build`:**

- Utilise le cache de build (archive, sources, compilation CMake)
- Compilation incrémentale : seuls les fichiers modifiés sont recompilés
- **Rapide** pour les compilations suivantes (~5-10 minutes au lieu de 30-60)
- Les outils (linuxdeploy, appimagetool) sont réutilisés s'ils existent déjà

**`./build.sh rebuild`:**

- Supprime `build/gnucash-x.xx_build/` (nettoyage du cache CMake)
- Force une recompilation complète depuis zéro
- **Nécessaire quand vous modifiez:**
  - Les options CMake dans `build-gnucash.sh`
  - Le `Dockerfile` (dépendances système)
  - Les scripts de compilation
- Garde l'archive et les sources (pas de re-téléchargement)

**`./build.sh clean`:**

- Nettoyage complet : supprime `build/`, `output/`, conteneurs et images Docker
- À utiliser quand vous voulez repartir de zéro
- Les outils seront retéléchargés au prochain build

**`./build.sh clean-deep`:**

- Fait un `clean` standard
- Plus : nettoie le cache Docker buildkit (layers)
- Garantit un état "comme la toute première fois"
- **Utile pour** : résoudre des problèmes persistants ou libérer de l'espace disque

#### Mode debug

Pour activer les logs détaillés pendant la compilation :

```bash
DEBUG=1 ./build.sh build
```

Cela affichera toutes les commandes exécutées (`set -x`).

Variables d'environnement utiles pour le débogage:

- GUILE_WARN_DEPRECATED=detailed : Affiche les warnings Guile

- GNC_DEBUG=1 : Active le mode debug de GnuCash

- LD_DEBUG=libs : Debug du chargement des bibliothèques

## Temps de compilation

| Scénario                            | Durée locale | Durée GitHub Actions |
| ----------------------------------- | ------------ | -------------------- |
| Première compilation complète       | 30-60 min    | 45-90 min            |
| Compilations suivantes (avec cache) | 5-10 min     | 10-20 min            |
| Rebuild après modification mineure  | 10-20 min    | 15-30 min            |

# 🎨 Personnalisation du build

## Options CMake

Modifier `build-gnucash.sh` :

```bash
cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITH_PYTHON=ON \          # Support Python
    -DWITH_AQBANKING=ON \       # Banking en ligne
    -DENABLE_BINRELOC=ON        # Requis pour AppImage
```

Après modification, faire un rebuild:

```bash
./build.sh rebuild
```

## Changer la version de GnuCash

**GitHub Actions:** Modifier les workflows:

```yaml
env:
  GNUCASH_VERSION: 5.15  # Nouvelle version
```

**Local:** Modifier `build-gnucash.sh` :

```bash
GNUCASH_VERSION="5.15"  # Nouvelle version
```

# 📥 Récupérer l'AppImage

### Depuis GitHub Actions

1. Onglet "Actions" → Workflow terminé
2. Section "Artifacts" → Télécharger
3. Ou depuis une Release (si créée via tag)

### Depuis le build local

Une fois la compilation terminée, l'AppImage se trouve dans :

```bash
./output/GnuCash-x.xx-x86_64.AppImage
```

# 🚀 Utiliser l'AppImage

```bash
chmod +x ./output/GnuCash-x.xx-x86_64.AppImage
./output/GnuCash-x.xx-x86_64.AppImage
```

L'AppImage est **portable** et peut être copiée sur n'importe quelle distribution Linux récente (glibc 2.35+).

# 🐛 Dépannage

### Débogage local

### Shell interactif

Pour investiguer les problèmes, ouvrez un shell dans le conteneur :

```bash
./shell.sh

# Dans le conteneur, vous pouvez :
# - Inspecter les sources
cd build/gnucash-x.xx

# - Voir le build
cd build/gnucash-x.xx_build

# - Vérifier les dépendances
ldd build/AppDir/usr/bin/gnucash

# - Installer des outils supplémentaires
sudo apt update && sudo apt install vim strace

# - Exécuter manuellement des étapes de compilation
cd build/gnucash-x.xx_build
cmake /workspace/build/gnucash-x.xx -DCMAKE_INSTALL_PREFIX=/usr/local
make -j$(nproc)
```

### Diagnostic de l'AppImage

```bash
./diagnose-appimage.sh output/GnuCash-5.14-x86_64.AppImage
```

### Mode debug

```bash
DEBUG=1 ./build.sh build
```

## Debug GitHub Actions

**Voir les logs détaillés:**

1. Actions → Workflow → Job → Step logs

**Activer le mode debug (workflow build-release.yml):**

1. Actions → Build and Release → Run workflow
2. Cocher "Enable debug mode"

**Re-run avec debug:**

1. Workflow terminé → "Re-run jobs"
2. Cocher "Enable debug logging"

## Problèmes courants

### Espace disque insuffisant (GitHub Actions)

Le workflow `build-release.yml` nettoie automatiquement. Si le problème persiste, voir [GITHUB_ACTIONS.md](GITHUB_ACTIONS.md#d%C3%A9pannage).

### Cache invalide

```bash
./build.sh clean-deep  # Local
```

Pour GitHub Actions: supprimer le cache manuellement dans Settings → Actions → Caches

### Erreur de segmentation (Segfault) à l'exécution de l'AppImage

Si l'AppImage plante avec "Erreur de segmentation", utilisez le script de diagnostic :

```bash
./diagnose-appimage.sh output/GnuCash-x.xx-x86_64.AppImage
```

Ce script va :

- Extraire l'AppImage
- Vérifier les dépendances manquantes
- Tester l'exécution avec strace
- Afficher les erreurs détaillées

**Solutions courantes :**

1. **Dépendances manquantes** : linuxdeploy devrait les collecter automatiquement. Vérifiez avec :
   
   ```bash
   ./diagnose-appimage.sh output/GnuCash-x.xx-x86_64.AppImage
   ```

2. **Conflit de bibliothèques** : Essayez de compiler en mode Debug :
   
   ```bash
   # Modifier build-gnucash.sh, ligne cmake:
   -DCMAKE_BUILD_TYPE=Debug
   ```

3. **Problème avec Python** : Essayez de désactiver Python :
   
   ```bash
   # Modifier build-gnucash.sh, ligne cmake:
   -DWITH_PYTHON=OFF
   ```

4. **Tester dans le conteneur** : Avant de créer l'AppImage :
   
   ```bash
   ./shell.sh
   cd build/AppDir
   ./usr/bin/gnucash --version
   ```

### Logs de compilation

Pour suivre la compilation en temps réel :

```bash
docker compose up --build
```

Pour voir uniquement les erreurs :

```bash
docker compose up --build 2>&1 | grep -i error
```

Pour logs détaillés :

```bash
DEBUG=1 ./build.sh build
```

## Personnalisation

### Options de compilation CMake

Vous pouvez modifier les options CMake dans `build-gnucash.sh` (lignes 53-58). Options courantes :

- `-DWITH_PYTHON=ON/OFF` : Support Python (défaut: ON)
- `-DCMAKE_BUILD_TYPE=Release/Debug` : Type de build (défaut: Release)
- `-DWITH_AQBANKING=ON/OFF` : Support banque en ligne (défaut: ON)
- `-DENABLE_BINRELOC=ON/OFF` : Relocalisation binaire pour AppImage (défaut: ON, **requis**)

Après modification, utilisez `./build.sh rebuild` pour forcer la reconfiguration CMake.

# Architecture technique

### Structure AppDir cohérente : /usr/local uniquement

```
AppDir/
├── AppRun                   ← Script de lancement
├── gnucash.desktop         ← Fichier .desktop (racine requise)
├── gnucash.png             ← Icône (racine requise)
└── usr/local/              ← Tout GnuCash est ici
    ├── bin/
    │   └── gnucash         ← Exécutable principal
    ├── lib/
    │   ├── libgnc*.so      ← Bibliothèques GnuCash
    │   └── gnucash/        ← Modules GnuCash (.so et .go)
    └── share/
        ├── applications/
        ├── icons/
        └── gnucash/        ← Données GnuCash
```

**Pourquoi /usr/local uniquement ?**

- ✅ Compatible avec BINRELOC (relocalisation binaire) :
  Avec prefix=/usr, le module GNUInstallDirs de CMake transforme automatiquement CMAKE_INSTALL_SYSCONFDIR=etc en /etc (chemin absolu) conformément aux standards GNU. Cela casse BINRELOC car /etc n'est pas sous le prefix.
  Avec /usr/local, CMake respecte sysconfdir=etc et produit /usr/local/etc comme attendu.
- ✅ Pas de confusion entre `/usr` et `/usr/local`

### Cache des outils

```
/workspace/build/
├── linuxdeploy-x86_64.AppImage    ← Téléchargé une seule fois
└── appimagetool-x86_64.AppImage   ← Téléchargé une seule fois

/usr/local/ (dans le conteneur Docker)
├── bin/
│   ├── linuxdeploy      → wrapper script
│   └── appimagetool     → wrapper script
└── share/
    ├── linuxdeploy/     → structure complète extraite
    └── appimagetool/    → structure complète extraite
```

Les outils sont :

1. Téléchargés dans `/workspace/build/` (volume monté, donc persistant)
2. Extraits complètement (toutes leurs dépendances incluses)
3. Installés dans `/usr/local/share/` du conteneur avec un wrapper dans `/usr/local/bin/`
4. Réutilisés aux prochaines exécutions sans re-téléchargement ni réinstallation

## Notes

- L'AppImage créée est **autonome** et contient toutes les dépendances
- Elle peut être exécutée sur la plupart des distributions Linux modernes (glibc 2.35+)
- La première compilation est longue, mais le cache accélère grandement les suivantes
- Les scripts peuvent être modifiés à chaud sans reconstruire l'image Docker
- Tout le contenu (sources, compilation, output) est accessible sur votre système de fichiers
- La structure "out-of-source build" facilite le nettoyage et le débogage

## Dépendances système requises dans l'AppImage

L'AppImage inclut automatiquement (via linuxdeploy) :

- Les dépendances GTK3, WebKit2, et autres bibliothèques système
- Les modules Guile et leurs dépendances
- Les schémas GSettings et données nécessaires

**Exclusions :**

- Bibliothèques système de base (libc, libm, etc.) : présentes sur tous les systèmes

## Licence

Ce projet est fourni tel quel, sans garantie. GnuCash est sous licence GPLv2+.
