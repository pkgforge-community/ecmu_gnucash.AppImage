#!/bin/bash
# Activer le mode debug si la variable DEBUG est définie
echo "DEBUG = $DEBUG"
if [ "${DEBUG}" = "1" ]; then
    set -x
fi
set -e

# Charge la version depuis .env si non déjà définie
if [ -z "$GNUCASH_VERSION" ] && [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
fi
# Quitte le script s'il manque cette variable à ce stade
: "${GNUCASH_VERSION:?La variable GNUCASH_VERSION doit être définie}"

# Organisation des répertoires :
# $SCRIPTPATH  : répertoire monté en /workspace dans docker (scripts + cache)
# ├─ /build    : sources et compilation
# └─ /output   : AppImage finale
SCRIPTPATH=$(cd $(dirname "$BASH_SOURCE") && pwd)
cd "$SCRIPTPATH"

# Nettoye l'ancien AppDir pour éviter les fichiers obsolètes
rm -rf build/AppDir 2>/dev/null || true
mkdir --parent build/AppDir

#region Téléchargement de GnuCash

echo "=== Téléchargement de GnuCash $GNUCASH_VERSION ==="

# Créer le répertoire de build s'il n'existe pas
mkdir -p build
pushd build

# Télécharger seulement si l'archive n'existe pas
if [ ! -f "gnucash-$GNUCASH_VERSION.tar.bz2" ]; then
    echo "Téléchargement de l'archive..."
    wget https://github.com/Gnucash/gnucash/releases/download/$GNUCASH_VERSION/gnucash-$GNUCASH_VERSION.tar.bz2
else
    echo "Archive déjà présente, téléchargement ignoré."
fi

# Extraire seulement si le répertoire n'existe pas
if [ ! -d "gnucash-$GNUCASH_VERSION" ]; then
    echo "Extraction de l'archive..."
    tar -xjf gnucash-$GNUCASH_VERSION.tar.bz2
else
    echo "Sources déjà extraites."
fi

popd

#endregion
#region Compilation

echo "=== Configuration avec CMake ==="
# Vérifier si le build existe déjà (maintenant à côté des sources)
BUILD_DIR="$SCRIPTPATH/build/gnucash-$GNUCASH_VERSION_build"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Premier build - création du répertoire et configuration CMake..."
    mkdir -p "$BUILD_DIR"
    pushd "$BUILD_DIR"

    # Configuration CMake avec options pour AppImage
    # -DCMAKE_INSTALL_PREFIX=/usr/local : Installation sous /usr/local (évite le comportement spécial)
    # -DCMAKE_BUILD_TYPE=Release : Build optimisé pour la production
    # -DWITH_PYTHON=ON : Active le support Python
    # -DENABLE_BINRELOC=ON : Active la relocalisation binaire (nécessaire pour AppImage)
    # -DCMAKE_INSTALL_SYSCONFDIR=etc : Avec prefix=/usr/local, produit /usr/local/etc (OK pour BINRELOC)
    # NOTE: On n'utilise pas GNC_UNINSTALLED car on veut une installation complète dans AppDir
    #   GNC_UNINSTALLED est uniquement pour exécuter GnuCash depuis le répertoire de build sans installer
    cmake "$SCRIPTPATH/build/gnucash-$GNUCASH_VERSION" \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release \
        -DWITH_PYTHON=ON \
        -DENABLE_BINRELOC=ON \
        -DCMAKE_INSTALL_SYSCONFDIR=etc

    echo "=== Compilation ==="
    make -j$(nproc)

    popd
else
    echo "Build existant détecté - compilation incrémentale..."
    pushd "$BUILD_DIR"
    
    # Compilation incrémentale (make détecte automatiquement les changements)
    echo "=== Compilation incrémentale ==="
    make -j$(nproc)

    popd
fi

#endregion
#region AppDir : Installation Gnucash

pushd "$BUILD_DIR"

echo "=== Installation dans AppDir ==="
DESTDIR="$SCRIPTPATH/build/AppDir" make install

popd

echo "=== Création de la structure AppImage ==="
pwd
pushd build

# Créer les répertoires nécessaires
mkdir -p AppDir/usr/local/share/applications
mkdir -p AppDir/usr/local/share/icons/hicolor/256x256/apps

# Copier le fichier .desktop à la racine de AppDir
cp AppDir/usr/local/share/applications/gnucash.desktop AppDir/

# Corriger le fichier .desktop pour l'AppImage
sed -i 's|Icon=gnucash-icon|Icon=gnucash|g' AppDir/gnucash.desktop
# S'assurer que Exec pointe vers le bon chemin
sed -i 's|^Exec=.*|Exec=gnucash|g' AppDir/gnucash.desktop

# Copier l'icône
if [ -f AppDir/usr/local/share/icons/hicolor/256x256/apps/gnucash-icon.png ]; then
    cp AppDir/usr/local/share/icons/hicolor/256x256/apps/gnucash-icon.png AppDir/gnucash.png
elif [ -f AppDir/usr/local/share/pixmaps/gnucash-icon.png ]; then
    cp AppDir/usr/local/share/pixmaps/gnucash-icon.png AppDir/gnucash.png
fi

popd

#endregion

# Fonction pour copier récursivement les dépendances d'une bibliothèque
dependencies_processed_file="/tmp/processed_libs.txt"
copy_dependencies() {
    local binary="$1"

    # Créer le fichier de suivi s'il n'existe pas
    touch "$dependencies_processed_file"

    # Obtenir les dépendances avec ldd
    ldd "$binary" 2>/dev/null | grep "=>" | awk '{print $3}' | while read dep; do
        if [ -n "$dep" ] && [ -f "$dep" ]; then
            local dep_basename=$(basename "$dep")
            local dep_realpath=$(readlink -f "$dep")
            
            # Vérifier si déjà traité
            if grep -q "^${dep_realpath}$" "$dependencies_processed_file" 2>/dev/null; then
                continue
            fi
            
            # Marquer comme traité
            echo "$dep_realpath" >> "$dependencies_processed_file"
            
            # Ignorer les bibliothèques système de base (déjà présentes partout)
            case "$dep_basename" in
                libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|ld-linux*.so*)
                    continue
                    ;;
            esac
            
            # Copier la dépendance si elle n'est pas déjà dans AppDir
            if [ ! -f "$SCRIPTPATH/build/AppDir/usr/local/lib/$dep_basename" ]; then
                cp -L "$dep" "$SCRIPTPATH/build/AppDir/usr/local/lib/" 2>/dev/null || true
            fi
            
            # Traiter récursivement les dépendances de cette bibliothèque
            copy_dependencies "$dep"
        fi
    done
}

#region AppDir : Copie les dépendances directes de GnuCash via ldd

echo "=== Création de l'AppImage ==="

# Utiliser linuxdeploy pour collecter les dépendances
echo ""
echo "=== Collecte des dépendances système ==="

# Définir les variables d'environnement pour linuxdeploy
export LD_LIBRARY_PATH="$SCRIPTPATH/build/AppDir/usr/local/lib:$SCRIPTPATH/build/AppDir/usr/local/lib/x86_64-linux-gnu:$SCRIPTPATH/build/AppDir/usr/local/lib/gnucash:${LD_LIBRARY_PATH}"

# STRATÉGIE RAPIDE : Au lieu d'appeler linuxdeploy pour chaque bibliothèque,
# on collecte d'abord toutes les dépendances nécessaires, puis on fait un seul appel à linuxdeploy

pushd build

echo "Collecte de la liste des dépendances à déployer..."
mkdir -p AppDir/usr/local/lib

# Nettoyer le fichier de suivi
rm -f "$dependencies_processed_file"

echo "Traitement de l'exécutable principal gnucash..."
copy_dependencies "AppDir/usr/local/bin/gnucash"

echo "Traitement des bibliothèques GnuCash..."
for lib in AppDir/usr/local/lib/libgnc-*.so; do
    if [ -f "$lib" ]; then
        echo "  - $(basename $lib)"
        copy_dependencies "$lib"
    fi
done

echo "Traitement des modules GnuCash..."
if [ -d "AppDir/usr/local/lib/gnucash" ]; then
    # Limiter aux .so principaux (pas tous les liens symboliques)
    find AppDir/usr/local/lib/gnucash -name "*.so" -type f | while read module; do
        echo "  - $(basename $module)"
        copy_dependencies "$module"
    done
fi

echo ""
echo "✅ Collecte des dépendances terminée"

popd

#endregion
#region AppDir : Copie les pilotes DBI/DBD (SQLite, etc.)

echo ""
echo "=== Copie des pilotes DBI/DBD ==="

# GnuCash utilise libdbi pour accéder aux bases de données
# Il faut copier les pilotes DBD (notamment sqlite3)

pushd build/AppDir/usr/local

# Trouver le répertoire des pilotes DBD
DBD_DIR=$(find /usr/lib -name "dbd" -type d 2>/dev/null | head -1)

if [ -n "$DBD_DIR" ] && [ -d "$DBD_DIR" ]; then
    echo "Répertoire DBD trouvé: $DBD_DIR"
    
    # Créer le répertoire de destination
    mkdir -p "./lib/x86_64-linux-gnu/dbd"
    
    # Copier tous les pilotes DBD
    echo "Copie des pilotes DBD..."
    cp -v "$DBD_DIR"/*.so "./lib/x86_64-linux-gnu/dbd/" 2>/dev/null || true
    
    # Copier les dépendances de chaque pilote
    for dbd_driver in "$DBD_DIR"/*.so; do
        if [ -f "$dbd_driver" ]; then
            echo "  Traitement de $(basename $dbd_driver)..."
            copy_dependencies "$dbd_driver"
        fi
    done
    
    echo "✅ Pilotes DBD copiés"
    ls -la "./lib/x86_64-linux-gnu/dbd/"
else
    echo "⚠️  ATTENTION: Répertoire DBD non trouvé!"
    echo "   Recherche des pilotes DBD..."
    
    # Recherche alternative des fichiers .so DBD
    find /usr/lib -name "libdbdsqlite3.so" -o -name "libdbd*.so" 2>/dev/null | while read dbd_file; do
        echo "  Trouvé: $dbd_file"
        mkdir -p "./lib/x86_64-linux-gnu/dbd"
        cp -v "$dbd_file" "./lib/x86_64-linux-gnu/dbd/"
        copy_dependencies "$dbd_file"
    done
fi

# Vérifier aussi libdbi elle-même
echo ""
echo "Vérification de libdbi..."
if [ ! -f "./lib/libdbi.so.1" ]; then
    LIBDBI_PATH=$(ldconfig -p | grep "libdbi.so.1 " | awk '{print $NF}' | head -1)
    if [ -n "$LIBDBI_PATH" ]; then
        echo "Copie de libdbi.so.1..."
        cp -L "$LIBDBI_PATH" "./lib/"
        copy_dependencies "$LIBDBI_PATH"
        echo "✅ libdbi copiée"
    else
        echo "⚠️  libdbi.so.1 non trouvée"
    fi
else
    echo "✅ libdbi déjà présente"
fi

popd

echo ""
echo "✅ Configuration DBD terminée"

#endregion
#region AppDir : copie manuellement Guile

# Copier explicitement Guile et ses dépendances critiques si pas déjà présentes
echo ""
echo "Vérification des dépendances critiques (Guile, etc.)..."
pushd build/AppDir/usr/local/lib
for critical_lib in libguile-3.0.so.1 libgc.so.1 libgmp.so.10 libunistring.so.2 libffi.so.8 libffi.so.7; do
    if [ ! -f "./$critical_lib" ]; then
        LIB_PATH=$(ldconfig -p | grep "$critical_lib " | awk '{print $NF}' | head -1)
        if [ -n "$LIB_PATH" ]; then
            echo "  Copie de $critical_lib..."
            cp -L "$LIB_PATH" "./" 2>/dev/null || true
            # Copier aussi ses dépendances
            copy_dependencies "$LIB_PATH"
        fi
    fi
done
popd

# Copier les fichiers Guile (nécessaire pour que Guile fonctionne)
echo ""
echo "=== Copie des fichiers Guile ==="

# Trouver le répertoire des fichiers Guile
GUILE_VERSION=$(guile --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' || echo "3.0")
GUILE_SHARE="/usr/share/guile/${GUILE_VERSION}"

if [ -d "$GUILE_SHARE" ]; then
    echo "Copie de Guile ${GUILE_VERSION} depuis ${GUILE_SHARE}..."
    pushd build/AppDir/usr/local

    mkdir -p ./share/guile
    cp -r "$GUILE_SHARE" ./share/guile
    
    # Copier aussi les fichiers compilés (.go)
    GUILE_LIB="/usr/lib/x86_64-linux-gnu/guile/${GUILE_VERSION}"
    if [ -d "$GUILE_LIB" ]; then
        mkdir -p ./lib/guile
        cp -r "$GUILE_LIB" ./lib/guile/
        echo "✅ Fichiers Guile compilés (.go) copiés"
    fi

    popd
    echo "✅ Fichiers Guile copiés (ice-9/boot-9.scm et autres)"
else
    echo "❌ ERREUR: Répertoire Guile non trouvé: $GUILE_SHARE"
    echo "Guile ne pourra pas démarrer dans l'AppImage!"
    exit 1
fi

#endregion
#region AppDir : Copie le runtime Python

echo ""
echo "=== Copie du runtime Python ==="

PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+')
echo "Version Python détectée: ${PYTHON_VERSION}"

pushd build

# 1. Copier la bibliothèque partagée libpython
echo "Copie de libpython${PYTHON_VERSION}..."
LIBPYTHON_PATH=$(ldconfig -p | grep "libpython${PYTHON_VERSION}.so.1.0" | awk '{print $NF}' | head -1)
if [ -n "$LIBPYTHON_PATH" ] && [ -f "$LIBPYTHON_PATH" ]; then
    mkdir -p AppDir/usr/local/lib
    cp -L "$LIBPYTHON_PATH" AppDir/usr/local/lib/
    
    # Créer les liens symboliques
    pushd AppDir/usr/local/lib
    ln -sf "libpython${PYTHON_VERSION}.so.1.0" "libpython${PYTHON_VERSION}.so.1"
    ln -sf "libpython${PYTHON_VERSION}.so.1.0" "libpython${PYTHON_VERSION}.so"
    popd
    
    echo "✅ libpython${PYTHON_VERSION}.so.1.0 copiée"
    
    # Copier ses dépendances
    copy_dependencies "$LIBPYTHON_PATH"
else
    echo "❌ ERREUR: libpython${PYTHON_VERSION}.so.1.0 introuvable!"
    echo "Python ne fonctionnera pas dans l'AppImage"
fi

# 2. Copier la bibliothèque standard Python
echo ""
echo "Copie de la bibliothèque standard Python ${PYTHON_VERSION}..."
PYTHON_LIB_SRC="/usr/lib/python${PYTHON_VERSION}"

if [ -d "$PYTHON_LIB_SRC" ]; then
    mkdir -p "AppDir/usr/local/lib/python${PYTHON_VERSION}"
    
    # Copier la bibliothèque standard
    echo "  Copie depuis ${PYTHON_LIB_SRC}..."
    cp -r "$PYTHON_LIB_SRC"/* "AppDir/usr/local/lib/python${PYTHON_VERSION}/"
    
    # Nettoyer après coup les éléments non désirés
    echo "  Nettoyage des fichiers inutiles..."
    find "AppDir/usr/local/lib/python${PYTHON_VERSION}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
    find "AppDir/usr/local/lib/python${PYTHON_VERSION}" -type f -name '*.pyc' -delete 2>/dev/null || true
    find "AppDir/usr/local/lib/python${PYTHON_VERSION}" -type f -name '*.pyo' -delete 2>/dev/null || true
    rm -rf "AppDir/usr/local/lib/python${PYTHON_VERSION}/test" 2>/dev/null || true
    rm -rf "AppDir/usr/local/lib/python${PYTHON_VERSION}/idlelib" 2>/dev/null || true
    rm -rf "AppDir/usr/local/lib/python${PYTHON_VERSION}/tkinter" 2>/dev/null || true
    rm -rf "AppDir/usr/local/lib/python${PYTHON_VERSION}/turtledemo" 2>/dev/null || true
    rm -f "AppDir/usr/local/lib/python${PYTHON_VERSION}/turtle.py" 2>/dev/null || true
    
    echo "✅ Bibliothèque standard Python copiée"
else
    echo "❌ ERREUR: Bibliothèque Python non trouvée à $PYTHON_LIB_SRC"
    echo "Python ne fonctionnera pas dans l'AppImage"
fi

# 3. Copier les modules d'extension dynamiques (.so)
echo ""
echo "Copie des modules d'extension Python..."
PYTHON_DYNLOAD_SRC="/usr/lib/python${PYTHON_VERSION}/lib-dynload"
if [ -d "$PYTHON_DYNLOAD_SRC" ]; then
    mkdir -p "AppDir/usr/local/lib/python${PYTHON_VERSION}/lib-dynload"
    pushd "AppDir/usr/local/lib/python${PYTHON_VERSION}/lib-dynload"

    cp -r "$PYTHON_DYNLOAD_SRC"/* . 2>/dev/null || true
    # Copier les dépendances de chaque module .so
    find . -name "*.so" -type f | while read module; do
        copy_dependencies "$module"
    done
    
    popd
    echo "✅ Modules d'extension copiés"
else
    echo "⚠️  Modules d'extension non trouvés à $PYTHON_DYNLOAD_SRC"
fi

# 4. Copier l'exécutable python3 (optionnel, utile pour le débogage)
echo ""
echo "Copie de l'exécutable python3..."
if [ -f "/usr/bin/python${PYTHON_VERSION}" ]; then
    mkdir -p AppDir/usr/local/bin
    pushd AppDir/usr/local/bin

    cp --dereference "/usr/bin/python${PYTHON_VERSION}" .
    ln -sf "python${PYTHON_VERSION}" "python3"
    ln -sf "python${PYTHON_VERSION}" "python"

    popd
    echo "✅ Exécutable Python copié"
fi

# 5. Vérifier les dépendances critiques de Python
echo ""
echo "Vérification des dépendances critiques de Python..."
for py_dep in libexpat.so.1 libz.so.1; do
    if [ ! -f "AppDir/usr/local/lib/$py_dep" ]; then
        DEP_PATH=$(ldconfig -p | grep "$py_dep " | awk '{print $NF}' | head -1)
        if [ -n "$DEP_PATH" ]; then
            echo "  Copie de $py_dep..."
            cp -L "$DEP_PATH" "AppDir/usr/local/lib/" 2>/dev/null || true
        fi
    fi
done

popd

echo ""
echo "✅ Runtime Python copié dans AppDir"

#endregion
#region AppDir : Finalisation avec linuxdeploy

# Installation de linuxdeploy
if [ ! -f "/usr/local/bin/linuxdeploy" ]; then
    echo "Téléchargement de linuxdeploy..."
    pushd build
    if [ ! -f "./linuxdeploy-x86_64.AppImage" ]; then
        wget -q --show-progress https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
        chmod +x ./linuxdeploy-x86_64.AppImage
    fi
    # Extraire l'AppImage pour l'utiliser dans Docker (évite les problèmes FUSE)
    ./linuxdeploy-x86_64.AppImage --appimage-extract >/dev/null 2>&1
    # Garder toute la structure squashfs-root dans /usr/local/share
    sudo mkdir -p /usr/local/share/linuxdeploy
    sudo cp -r squashfs-root/* /usr/local/share/linuxdeploy/
    # Créer un wrapper dans /usr/local/bin
    echo '#!/bin/bash' | sudo tee /usr/local/bin/linuxdeploy > /dev/null
    echo 'exec /usr/local/share/linuxdeploy/AppRun "$@"' | sudo tee -a /usr/local/bin/linuxdeploy > /dev/null
    sudo chmod +x /usr/local/bin/linuxdeploy
    rm -rf squashfs-root
    popd
    echo "✅ linuxdeploy installé"
else
    echo "✅ linuxdeploy déjà installé"
fi

pushd build

# Maintenant, un SEUL appel à linuxdeploy pour l'exécutable principal
# (cela va aussi vérifier/compléter les dépendances et créer les liens symboliques)
echo ""
echo "Finalisation avec linuxdeploy..."
linuxdeploy --appdir=AppDir --executable=AppDir/usr/local/bin/gnucash

echo ""
echo "Déplace les fichiers de /usr vers /usr/local (bin, lib)..."
cp --recursive AppDir/usr/bin   AppDir/usr/local/ && rm --recursive AppDir/usr/bin
cp --recursive AppDir/usr/lib   AppDir/usr/local/ && rm --recursive AppDir/usr/lib
cp --recursive AppDir/usr/share AppDir/usr/local/ && rm --recursive AppDir/usr/share

popd

#endregion
#region AppDir : Vérifications

echo ""
echo "=== Vérification des dépendances ==="

pushd build

echo "Dépendances de gnucash:"
if ldd AppDir/usr/local/bin/gnucash | grep "not found"; then
    echo "⚠️  ATTENTION: Dépendances manquantes détectées!"
else
    echo "✅ Toutes les dépendances directes sont présentes"
fi

echo ""
echo "Vérification des modules GnuCash..."
# Vérifier aussi les bibliothèques GnuCash
GNUCASH_MODULES=$(find AppDir/usr/local/lib/gnucash -name "*.so*" -type f 2>/dev/null | head -5)
if [ -n "$GNUCASH_MODULES" ]; then
    echo "$GNUCASH_MODULES" | while read lib; do
        missing=$(ldd "$lib" 2>/dev/null | grep "not found" || true)
        if [ -n "$missing" ]; then
            echo "⚠️  Dépendances manquantes pour $(basename $lib):"
            echo "$missing"
        fi
    done
    echo "✅ Vérification des modules terminée"
else
    echo "⚠️  Aucun module GnuCash trouvé dans AppDir/usr/local/lib/gnucash"
fi

popd

#endregion
#region AppImage : Création

# Installation de appimagetool
if [ ! -f "/usr/local/bin/appimagetool" ]; then
    echo "Téléchargement de appimagetool..."
    pushd build
    if [ ! -f "./appimagetool-x86_64.AppImage" ]; then
        wget -q --show-progress https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
        chmod +x ./appimagetool-x86_64.AppImage
    fi
    # Extraire l'AppImage pour l'utiliser dans Docker (évite les problèmes FUSE)
    ./appimagetool-x86_64.AppImage --appimage-extract >/dev/null 2>&1
    # Garder toute la structure squashfs-root dans /usr/local/share
    sudo mkdir -p /usr/local/share/appimagetool
    sudo cp -r squashfs-root/* /usr/local/share/appimagetool/
    # Créer un wrapper dans /usr/local/bin
    echo '#!/bin/bash' | sudo tee /usr/local/bin/appimagetool > /dev/null
    echo 'exec /usr/local/share/appimagetool/AppRun "$@"' | sudo tee -a /usr/local/bin/appimagetool > /dev/null
    sudo chmod +x /usr/local/bin/appimagetool
    rm -rf squashfs-root
    popd
    echo "✅ appimagetool installé"
else
    echo "✅ appimagetool déjà installé"
fi

pushd build

# Créer le script AppRun (tout est dans /usr/local maintenant)
cat > AppDir/AppRun << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}

# CORRECTION gvfs : Empêcher le chargement des modules GIO du système pour éviter les conflits de version avec GLib (erreur g_task_set_static_name)
unset GIO_MODULE_DIR
unset GIO_EXTRA_MODULES

# CORRECTION Guile : Définir où Guile doit chercher ses fichiers ice-9/boot-9.scm et autres bibliothèques Scheme de base
export GUILE_LOAD_PATH="${HERE}/usr/local/share/guile/3.0:${HERE}/usr/local/share/guile/site/3.0"
export GUILE_LOAD_COMPILED_PATH="${HERE}/usr/local/lib/guile/3.0/site-ccache:${HERE}/usr/local/lib/guile/3.0/ccache"

export PYTHONHOME="${HERE}/usr/local"

# Chemins des bibliothèques
export PATH="${HERE}/usr/local/bin:${PATH}"

# LD_LIBRARY_PATH incluant TOUS les répertoires de bibliothèques
# Ordre d'importance : local d'abord (GnuCash), puis système (dépendances)
export LD_LIBRARY_PATH="${HERE}/usr/local/lib:${HERE}/usr/local/lib/x86_64-linux-gnu:${HERE}/usr/local/lib/gnucash:${LD_LIBRARY_PATH}"

# Chemins des données et ressources
export XDG_DATA_DIRS="${HERE}/usr/local/share:${XDG_DATA_DIRS}"
export GSETTINGS_SCHEMA_DIR="${HERE}/usr/local/share/glib-2.0/schemas:${GSETTINGS_SCHEMA_DIR}"

# Variables spécifiques à GnuCash
export GNC_MODULE_PATH="${HERE}/usr/local/lib/gnucash"
export GNC_DBD_DIR="${HERE}/usr/local/lib/x86_64-linux-gnu/dbd"

# Debug: décommenter pour afficher les chemins
# echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"
# echo "GNC_MODULE_PATH=$GNC_MODULE_PATH"
# echo "GUILE_LOAD_PATH=$GUILE_LOAD_PATH"

exec "${HERE}/usr/local/bin/gnucash" "$@"
EOF

chmod +x AppDir/AppRun

# Créer l'AppImage avec appimagetool
echo ""
echo "=== Création de l'AppImage ==="
mkdir -p "$SCRIPTPATH/output"
ARCH=x86_64 appimagetool --no-appstream AppDir "$SCRIPTPATH/output/GnuCash-$GNUCASH_VERSION-x86_64.AppImage"

echo ""
echo "=== AppImage créée avec succès ==="
ls -lh "$SCRIPTPATH/output/GnuCash-$GNUCASH_VERSION-x86_64.AppImage"

popd

#endregion
