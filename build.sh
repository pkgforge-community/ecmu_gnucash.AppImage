#!/bin/bash
# Script helper pour compiler GnuCash AppImage
set -e

function show_help {
    echo "Usage: ./build.sh [OPTION]"
    echo ""
    echo "Options:"
    echo "  build       - Compilation normale (réutilise le cache)"
    echo "  rebuild     - Recompilation complète (nettoie le cache de build)"
    echo "  clean       - Nettoie tout (cache + image Docker + volumes)"
    echo "  clean-deep  - Nettoyage approfondi (+ cache Docker buildkit)"
    echo "  help        - Affiche cette aide"
    echo ""
    echo "Exemples:"
    echo "  ./build.sh build       # Compilation rapide avec cache"
    echo "  ./build.sh rebuild     # Recompilation après modification du script"
    echo "  ./build.sh clean       # Tout nettoyer avant de recommencer"
    echo "  ./build.sh clean-deep  # Nettoyage complet incluant le cache Docker"
}

function build_normal {
    echo "=== Compilation normale avec cache ==="
    docker compose up --build
}

function rebuild_full {
    echo "=== Recompilation complète (suppression du cache de build) ==="
    echo "Arrêt des conteneurs..."
    docker compose down
    
    echo "Suppression du cache de build local..."
    rm -rf build/gnucash-5.14_build 2>/dev/null || true
    
    echo "Démarrage de la compilation..."
    docker compose up --build
}

function clean_all {
    echo "=== Nettoyage complet ==="
    echo "Arrêt et suppression des conteneurs..."
    docker compose down --volumes --remove-orphans
    
    echo "Suppression des répertoires de build et d'output..."
    rm -rf build/gnucash-5.14_build 2>/dev/null || true
    rm -rf build/AppDir 2>/dev/null || true
    rm -rf output 2>/dev/null || true
    
    echo "Suppression des images Docker de ce projet..."
    docker compose down --rmi all --volumes
    
    echo ""
    echo "✅ Nettoyage terminé !"
    echo ""
    echo "Si vous voulez aussi nettoyer le cache Docker buildkit, utilisez:"
    echo "  ./build.sh clean-deep"
}

function clean_deep {
    echo "=== Nettoyage approfondi ==="
    
    # D'abord faire le nettoyage standard
    clean_all
    # Ensuite va plus loin supprimant complètement le build, donc les outils téléchargés pour cache
    rm -rf build 2>/dev/null || true

    echo ""
    echo "Nettoyage du cache Docker buildkit..."
    docker builder prune -af

    echo ""
    echo "Liste des volumes Docker restants (si présents):"
    docker volume ls | grep gnucash || echo "  (aucun volume gnucash trouvé)"

    echo ""
    echo "✅ Nettoyage approfondi terminé !"
    echo ""
    echo "L'image sera entièrement reconstruite au prochain build,"
    echo "comme lors de la toute première exécution."
}

# Créer le répertoire output s'il n'existe pas
mkdir -p output

# Parser les arguments
case "${1:-build}" in
    build)
        build_normal
        ;;
    rebuild)
        rebuild_full
        ;;
    clean)
        clean_all
        ;;
    clean-deep)
        clean_deep
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Option inconnue: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
