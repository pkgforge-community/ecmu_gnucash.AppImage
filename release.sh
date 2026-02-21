#!/bin/bash
# Script helper pour créer des releases GitHub

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function show_help {
    echo "Usage: ./release.sh [VERSION]"
    echo ""
    echo "Crée et pousse un tag de version pour déclencher une release GitHub."
    echo ""
    echo "Arguments:"
    echo "  VERSION    Version à releaser (ex: 5.14, 5.15-beta1)"
    echo ""
    echo "Exemples:"
    echo "  ./release.sh 5.14           # Release stable"
    echo "  ./release.sh 5.15-rc1       # Release candidate"
    echo "  ./release.sh 5.15-beta1     # Beta release"
    echo ""
    echo "Le script va:"
    echo "  1. Vérifier que le repository est propre"
    echo "  2. Créer un tag annoté \$VERSION"
    echo "  3. Pousser le tag vers GitHub"
    echo "  4. GitHub Actions créera automatiquement la release"
}

function check_git_status {
    if ! git diff-index --quiet HEAD --; then
        echo "❌ Erreur: Le repository a des changements non commités"
        echo ""
        git status --short
        echo ""
        echo "Veuillez commiter ou stash vos changements avant de créer une release."
        exit 1
    fi
}

function check_remote {
    if ! git remote get-url origin >/dev/null 2>&1; then
        echo "❌ Erreur: Aucun remote 'origin' configuré"
        echo ""
        echo "Configurez d'abord un remote GitHub:"
        echo "  git remote add origin https://github.com/USERNAME/REPO.git"
        exit 1
    fi
}

function create_release {
    VERSION="$1"
    TAG="${VERSION}"
    
    echo "=== Création de la release $TAG ==="
    echo ""
    
    # Vérifications
    echo "Vérification du statut Git..."
    check_git_status
    check_remote
    
    # Vérifier que le tag n'existe pas déjà
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        echo "❌ Erreur: Le tag $TAG existe déjà"
        echo ""
        echo "Pour recréer le tag:"
        echo "  git tag -d $TAG"
        echo "  git push origin :refs/tags/$TAG"
        echo "  ./release.sh $VERSION"
        exit 1
    fi
    
    # Afficher les derniers commits
    echo ""
    echo "Derniers commits qui seront inclus dans la release:"
    echo ""
    git log --oneline -10
    echo ""
    
    # Confirmation
    read -p "Créer la release $TAG ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Annulé"
        exit 1
    fi
    
    # Créer le tag
    echo ""
    echo "Création du tag $TAG..."
    git tag -a "$TAG" -m "Release GnuCash AppImage $VERSION"
    
    # Pousser le tag
    echo "Push du tag vers GitHub..."
    git push origin "$TAG"
    
    echo ""
    echo "✅ Tag $TAG créé et poussé avec succès !"
    echo ""
    echo "GitHub Actions va maintenant:"
    echo "  1. Compiler l'AppImage GnuCash $VERSION"
    echo "  2. Créer une release GitHub"
    echo "  3. Uploader l'AppImage et les checksums"
    echo ""
    echo "Suivez l'avancement dans l'onglet Actions:"
    REMOTE_URL=$(git remote get-url origin)
    REPO_URL=$(echo "$REMOTE_URL" | sed -e 's/git@github.com:/https:\/\/github.com\//' -e 's/\.git$//')
    echo "  $REPO_URL/actions"
    echo ""
    echo "La release sera disponible dans:"
    echo "  $REPO_URL/releases/tag/$TAG"
}

# Parse arguments
case "${1:-}" in
    ""|-h|--help|help)
        show_help
        exit 0
        ;;
    *)
        VERSION="$1"
        
        # Valider le format de version (basique)
        if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[a-zA-Z0-9]+)?$ ]]; then
            echo "❌ Format de version invalide: $VERSION"
            echo ""
            echo "Formats valides:"
            echo "  5.14.0"
            echo "  5.15.0-rc1"
            echo "  5.15.0-beta1"
            exit 1
        fi
        
        create_release "$VERSION"
        ;;
esac
