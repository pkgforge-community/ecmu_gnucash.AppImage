#!/bin/bash
# Script pour ouvrir un shell interactif dans le conteneur de build

echo "=== Ouverture d'un shell interactif dans le conteneur ==="
echo "Utilisateur: docker (avec droits sudo sans mot de passe)"
echo ""

# Construire l'image si nécessaire
docker compose build

# Lancer un shell interactif
docker compose run --rm gnucash-builder /bin/bash
