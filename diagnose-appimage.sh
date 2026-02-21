#!/bin/bash
# Script de diagnostic pour l'AppImage GnuCash

APPIMAGE="$1"

if [ -z "$APPIMAGE" ] || [ ! -f "$APPIMAGE" ]; then
    echo "Usage: $0 <chemin-vers-AppImage>"
    echo "Exemple: $0 output/GnuCash-5.14-x86_64.AppImage"
    exit 1
fi

echo "=== Diagnostic de l'AppImage GnuCash ==="
echo "AppImage: $APPIMAGE"
echo ""

# Extraire l'AppImage
echo "=== Extraction de l'AppImage ==="
EXTRACT_DIR="/tmp/gnucash-appimage-extract-$$"
chmod +x "$APPIMAGE"
"$APPIMAGE" --appimage-extract >/dev/null 2>&1
mv squashfs-root "$EXTRACT_DIR"

echo "Extrait dans: $EXTRACT_DIR"
echo ""

# Vérifier la structure
echo "=== Structure de l'AppImage ==="
ls -la "$EXTRACT_DIR/"
echo ""

# Vérifier l'exécutable principal
echo "=== Vérification de l'exécutable gnucash ==="
GNUCASH_BIN="$EXTRACT_DIR/usr/bin/gnucash"
if [ ! -f "$GNUCASH_BIN" ]; then
    echo "❌ Exécutable non trouvé à: $GNUCASH_BIN"
    echo "Recherche de gnucash..."
    find "$EXTRACT_DIR" -name "gnucash" -type f
else
    echo "✅ Exécutable trouvé: $GNUCASH_BIN"
    file "$GNUCASH_BIN"
fi
echo ""

# Vérifier les dépendances manquantes
echo "=== Vérification des dépendances ==="
if [ -f "$GNUCASH_BIN" ]; then
    echo "Dépendances manquantes:"
    LD_LIBRARY_PATH="$EXTRACT_DIR/usr/lib:$EXTRACT_DIR/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH" \
        ldd "$GNUCASH_BIN" | grep "not found" || echo "✅ Aucune dépendance manquante"
    
    echo ""
    echo "Toutes les dépendances:"
    LD_LIBRARY_PATH="$EXTRACT_DIR/usr/lib:$EXTRACT_DIR/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH" \
        ldd "$GNUCASH_BIN" | head -20
fi
echo ""

# Vérifier les bibliothèques GnuCash
echo "=== Bibliothèques GnuCash présentes ==="
find "$EXTRACT_DIR" -name "libgnc*.so*" -type f | head -10
echo ""

# Vérifier le script AppRun
echo "=== Contenu du script AppRun ==="
if [ -f "$EXTRACT_DIR/AppRun" ]; then
    cat "$EXTRACT_DIR/AppRun"
else
    echo "❌ AppRun non trouvé"
fi
echo ""

# Essayer d'exécuter avec strace pour voir où ça plante
echo "=== Test d'exécution avec strace (premières erreurs) ==="
if command -v strace >/dev/null 2>&1; then
    echo "Exécution de strace (Ctrl+C pour arrêter)..."
    timeout 5 strace "$EXTRACT_DIR/AppRun" 2>&1 | tail -50
else
    echo "⚠️  strace non installé. Installez-le avec: sudo apt install strace"
fi
echo ""

# Essayer d'exécuter directement
echo "=== Test d'exécution directe ==="
echo "Tentative d'exécution..."
cd "$EXTRACT_DIR"
LD_LIBRARY_PATH="$EXTRACT_DIR/usr/lib:$EXTRACT_DIR/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH" \
    "$GNUCASH_BIN" --version 2>&1 || echo "❌ Échec de l'exécution"

echo ""
echo "=== Fin du diagnostic ==="
echo "Répertoire d'extraction conservé: $EXTRACT_DIR"
echo "Pour nettoyer: rm -rf $EXTRACT_DIR"
