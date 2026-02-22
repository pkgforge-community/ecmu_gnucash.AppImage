# GitHub Actions - Guide d'utilisation

Ce projet utilise GitHub Actions pour automatiser la construction de l'AppImage GnuCash.

## ⚙️ Workflows disponibles

### 1. Build AppImage (`build-appimage.yml`)

Build standard pour CI/CD, avec cache optimisé et upload automatique des AppImages.

**Déclenchement :**

- Push sur `main` ou `develop`
- Pull requests vers `main`
- Manuellement via l'interface GitHub
- Lors de la création d'une release

**Ce qu'il fait :**

- Construit l'AppImage de GnuCash
- Met en cache les outils (linuxdeploy, appimagetool)
- Upload l'AppImage comme artifact
- Génère les checksums SHA256

**Utilisation manuelle :**

1. Aller dans l'onglet "Actions" du repository
2. Sélectionner "Build GnuCash AppImage"
3. Cliquer sur "Run workflow"
4. Choisir la branche
5. Cliquer sur "Run workflow"

**Récupérer l'AppImage :**

- Aller dans l'onglet "Actions"
- Cliquer sur le workflow terminé
- Télécharger l'artifact dans la section "Artifacts"

### 2. Build and Release (Advanced) (`build-release.yml`)

Workflow avancé pour releases, avec un mode debug disponible.

**Déclenchement :**

- Push d'un tag de version (`v*`)
- Manuellement avec option debug

**Ce qu'il fait :**

- Build optimisé avec cache Docker layers
- Vérification de l'AppImage
- Création automatique d'une release GitHub
- Upload des assets (AppImage + checksums)
- Génération de release notes

**Créer une release :**

```bash
# Créer et pousser un tag
git tag -a v5.14.0 -m "GnuCash 5.14 AppImage"
git push origin v5.14.0
```

Le workflow créera automatiquement une release avec l'AppImage.

**Build manuel avec debug :**

1. Onglet "Actions" → "Build and Release GnuCash AppImage (Advanced)"
2. "Run workflow"
3. Cocher "Enable debug mode"
4. "Run workflow"

### 3. Nightly Build (`nightly.yml`)

Builds quotidiens automatiques avec des tests de stabilité.

**Déclenchement :**

- Tous les jours à 2h00 UTC
- Manuellement

**Ce qu'il fait :**

- Build quotidien pour tester la stabilité
- Conservation de 14 jours d'artifacts
- Utilise un cache dédié

**Désactiver les nightly builds :**
Supprimer ou commenter la section `schedule:` dans `nightly.yml`

### 4. Build avec version upstream (check-new-version.yml)

Flux complet :

```
Tous les lundis à 6h UTC : check-new-version.yml
├── API GitHub → dernier tag Gnucash (ex: 5.15)
└── API GitHub → release 5.15 existe dans votre repo ?
    ├── OUI
    |   └── stop, rien à faire
    └── NON
        └── Définit la version à 5.15 et le drapeau pour déclencher le job trigger-build
        └── trigger-build appelle l'action build-release.yml par workflow_call avec la version 5.15
```

### 4. Validation des Pull Requests (`pr-validation.yml`)

**Ce qu'il fait :**

- Vérification syntaxe shell/YAML

- Scan de sécurité

- Test de build Docker

## Configuration

### Variables d'environnement

Les variables d'environnement principales, comme `GNUCASH_VERSION`, sont lues dans le fichier `.env`.

`$GITHUB_ENV` est le mécanisme GitHub Actions pour propager des variables entre steps. Après ce step, `${{ env.GNUCASH_VERSION }}` est disponible dans tous les steps suivants du job, y compris les clés de cache.

### Secrets requis

Aucun secret n'est requis ! Le workflow utilise automatiquement `GITHUB_TOKEN` fourni par GitHub Actions.

### Optimisations de cache

Les workflows utilisent plusieurs niveaux de cache :

1. **Docker layers** (build-release.yml uniquement)
   
   - Cache les layers Docker pour accélérer le build de l'image
   - Clé: basée sur le hash du Dockerfile

2. **Artifacts de build**
   
   - Cache les outils téléchargés (linuxdeploy, appimagetool)
   - Cache l'archive source GnuCash
   - Clé: basée sur la version + hash des scripts

3. **Build directory partiel**
   
   - Ne cache PAS `gnucash-x.xx_build/` (trop volumineux)
   - GitHub Actions cache limité à 10GB par repository

### Limites GitHub Actions

- **Temps max par job:** 6 heures (notre timeout: 2h)
- **Espace disque:** ~14GB disponible (nettoyé dans build-release.yml)
- **Cache max:** 10GB par repository
- **Retention artifacts:** 90 jours max (configurable)

## Dépannage

### Le build échoue avec "No space left on device"

Le workflow `build-release.yml` nettoie déjà automatiquement l'espace. Si le problème persiste :

1. Réduire la taille du cache en excluant plus de fichiers
2. Désactiver temporairement le cache Docker layers

### Le build est trop long (> 2h)

Vérifier :

- Le cache fonctionne correctement
- Les logs pour identifier les étapes lentes
- Augmenter le timeout si nécessaire :

```yaml
timeout-minutes: 180  # 3 heures
```

### L'AppImage n'est pas uploadée

Vérifier les logs du step "Upload AppImage artifact". Causes courantes :

- Le fichier n'existe pas dans `output/`
- Permissions insuffisantes
- Le job a timeout

### Impossible de télécharger l'artifact

Les artifacts expirent après la durée de rétention (défaut: 30-90 jours).
Pour les conserver plus longtemps, utilisez les releases.

## Personnalisation

### Changer la fréquence des nightly builds

Modifier le cron dans `nightly.yml` :

```yaml
schedule:
  - cron: '0 2 * * 1'  # Tous les lundis à 2h00 UTC
  - cron: '0 14 * * 5' # Tous les vendredis à 14h00 UTC
```

Syntaxe cron: `minute heure jour-du-mois mois jour-de-la-semaine`

### Ajouter des notifications

Exemple pour Slack :

```yaml
- name: Notify Slack
  if: always()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

### Tester sur plusieurs distributions

Ajouter une matrix strategy :

```yaml
jobs:
  build:
    strategy:
      matrix:
        ubuntu: [20.04, 22.04, 24.04]
    runs-on: ubuntu-${{ matrix.ubuntu }}
```

## Bonnes pratiques

### Pour les développeurs

1. **Tester localement avant de push :**
   
   ```bash
   ./build.sh build
   ```

2. **Utiliser des branches feature :**
   
   - Les PRs vers `main` déclenchent automatiquement un build
   - Vérifier que le build passe avant de merger

3. **Créer des releases régulièrement :**
   
   - Utiliser le versioning sémantique (v5.14.0, v5.14.1, etc.)
   - Laisser le workflow générer les release notes

### Pour les releases

1. **Versionning :**
   
   ```bash
   # Release stable
   git tag -a v5.14.0 -m "GnuCash 5.14.0"
   
   # Pre-release
   git tag -a v5.14.0-rc1 -m "Release Candidate 1"
   git tag -a v5.14.0-beta1 -m "Beta 1"
   ```

2. **Vérification avant release :**
   
   - Tester manuellement le workflow sur une branche
   - Vérifier les checksums
   - Tester l'AppImage sur différentes distributions

3. **Communication :**
   
   - Les release notes sont auto-générées
   - Ajouter des notes manuelles si nécessaire dans la release GitHub

## Monitoring

### Suivre l'état des builds

- Badge de status : ajouter dans le README.md

```markdown
[![Build Status](https://github.com/ecmu/gnucash.AppImage/workflows/Build%20GnuCash%20AppImage/badge.svg)](https://github.com/VOTRE-USERecmuO/actions)
```

### Logs

- Tous les logs sont disponibles dans l'onglet "Actions"
- Les build logs sont uploadés comme artifacts (7 jours de rétention)
- Activer le mode debug pour plus de détails

## FAQ

**Q: Pourquoi avoir 3 workflows différents ?**

R: 

- `build-appimage.yml` : Simple, pour le développement quotidien
- `build-release.yml` : Optimisé avec cache avancé pour les releases
- `nightly.yml` : Tests automatiques de stabilité

**Q: Peut-on construire plusieurs versions de GnuCash ?**

R: Oui, utiliser une matrix strategy ou créer des branches par version.

**Q: Comment activer le mode debug ?**

R: 

- Workflow `build-release.yml` : option dans le formulaire de lancement manuel
- Autres workflows : modifier temporairement `DEBUG=1` dans le fichier

**Q: Les artifacts sont-ils publics ?**

R: Par défaut, les artifacts sont visibles uniquement par ceux qui ont accès au repository.
Les releases sont publiques si le repository est public.

## Support

En cas de problème :

1. Consulter les logs du workflow
2. Tester localement avec `./build.sh build`
3. Ouvrir une issue avec les logs du workflow
