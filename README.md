# Pre-commit Hooks for Kubernetes and Helm

A collection of pre-commit hooks for validating Kubernetes manifests and Helm charts in ArgoCD-managed repositories.

## Available Hooks

This repository provides specialized hooks for different validation needs. You can use them individually for targeted validation or together for comprehensive coverage.

### helm-template-all (Recommended)

**Comprehensive validation** - validates all Helm charts and ApplicationSets in one pass.

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-template-all
```

**What it validates:**
- Custom Helm charts (with Chart.yaml)
- Values-only charts (referencing upstream charts)
- ApplicationSet YAML syntax
- Automatically skips git-based charts

**Use this when:** You want complete validation with a single hook.

---

### helm-validate-custom-charts

**Validates custom Helm charts** - only charts with Chart.yaml files.

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-validate-custom-charts
```

**What it validates:**
- Charts with Chart.yaml
- Automatically builds dependencies
- Runs `helm template` to validate rendering

**Use this when:** You only want to validate custom charts, not upstream charts.

---

### helm-validate-values-only

**Validates values-only charts** - charts that reference upstream Helm repositories.

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-validate-values-only
```

**What it validates:**
- Directories with values.yaml but no Chart.yaml
- Extracts chart info from ApplicationSets
- Validates against upstream chart versions
- Automatically skips git-based charts

**Use this when:** You only want to validate values files for upstream charts.

---

### helm-validate-appsets

**Validates ApplicationSet files** - YAML syntax and structure validation.

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-validate-appsets
```

**What it validates:**
- ApplicationSet YAML syntax
- Required fields (kind, metadata, spec)
- Template structure

**Use this when:** You want to validate ApplicationSet definitions independently.

---

### helm-template-validate (Legacy)

**Backward compatibility hook** - same as helm-template-all.

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-template-validate
```

**Note:** This hook is kept for backward compatibility. New projects should use `helm-template-all` instead.

---

## Hook Combinations

### Option 1: Comprehensive (Recommended)
Use a single hook for everything:

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-template-all
```

### Option 2: Granular Control
Use separate hooks for different file types:

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-validate-custom-charts
      - id: helm-validate-values-only
      - id: helm-validate-appsets
```

**Benefits of granular approach:**
- Faster execution (only relevant hooks run)
- Better error isolation
- More control over what gets validated

### Option 3: Custom Mix
Mix and match based on your needs:

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-validate-custom-charts  # Always validate custom charts
      - id: helm-validate-appsets        # Always validate ApplicationSets
      # Skip values-only validation in CI
```

### Option 4: Limit to Specific Directories

Use the `files` parameter to restrict hooks to specific paths:

```yaml
repos:
 - repo: https://github.com/ngamber/pre-commit
   rev: main
   hooks:
     - id: helm-validate-custom-charts
       files: ^argocd/(grafana|mimir)/  # Only validate grafana and mimir
     - id: helm-validate-values-only
       files: ^argocd/loki/  # Only validate loki values
```

**Use cases:**
- Testing changes in specific charts
- Excluding problematic charts temporarily
- Faster validation during development

---

## Features

### Intelligent Chart Detection
- Automatically identifies chart types
- Handles custom charts with dependencies
- Parses ApplicationSets for upstream chart info
- Skips git-based charts (not applicable for validation)

### ApplicationSet Support
- Extracts chart information from ApplicationSet files
- Resolves templated versions (e.g., `{{.values.targetRevision}}`)
- Supports both Helm repository and git-based charts

### Detailed Error Reporting
- Color-coded output (✓ success, ✗ failure)
- Shows validation errors with context
- Summary statistics for each validation run

### Dependency Management
- Automatically runs `helm dependency build` for custom charts
- Handles charts with Chart.lock files
- Validates dependency versions

---

## Requirements

### Required Tools

```bash
# Helm CLI
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# yq (YAML processor) - go-yq, not python-yq
brew install yq  # macOS
# or
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

### Repository Structure

Expected directory structure for ArgoCD repositories:

```
your-repo/
├── argocd/                    # Helm chart directories
│   ├── custom-app/           # Custom chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       └── deployment.yaml
│   ├── upstream-app/         # Values-only chart
│   │   └── values.yaml
│   └── another-app/
│       └── values.yaml
└── argo-cd/
    └── appsets/              # ApplicationSet definitions
        ├── custom-app/
        │   └── custom-app.yaml
        ├── upstream-app/
        │   └── upstream-app.yaml
        └── another-app/
            └── another-app.yaml
```

---

## How It Works

### Custom Chart Validation

1. Detects charts with `Chart.yaml`
2. Checks for dependencies in Chart.yaml
3. Runs `helm dependency build` if needed
4. Validates with `helm template`

```bash
helm dependency build /path/to/chart
helm template test-release /path/to/chart
```

### Values-Only Chart Validation

1. Detects directories with `values.yaml` but no `Chart.yaml`
2. Finds corresponding ApplicationSet file
3. Extracts chart name, repo URL, and version
4. Validates with upstream chart

```bash
helm template test-release CHART_NAME \
  --repo REPO_URL \
  --version VERSION \
  -f values.yaml
```

### ApplicationSet Validation

1. Validates YAML syntax
2. Checks for required fields
3. Verifies kind is "ApplicationSet"

---

## Installation

### 1. Install Pre-commit

```bash
pip install pre-commit
```

### 2. Add to Your Project

Create `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main  # or use a specific version tag
    hooks:
      - id: helm-template-all
```

### 3. Install the Hooks

```bash
pre-commit install
```

### 4. Run Manually (Optional)

Test before committing:

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hook on all files
pre-commit run helm-template-all --all-files
pre-commit run helm-validate-custom-charts --all-files

# Run on specific files
pre-commit run --files argocd/grafana/values.yaml
pre-commit run --files argocd/grafana/Chart.yaml argocd/grafana/values.yaml

# Run on specific directories
pre-commit run --files argocd/grafana/*
pre-commit run --files argocd/*/values.yaml

# Run only on staged files (default behavior)
pre-commit run
```

---

## ApplicationSet Format

For values-only charts, ApplicationSets must contain chart information:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: upstream-app
spec:
  generators:
    - clusters:
        values:
          targetRevision: "1.2.3"  # Can be referenced in template
  template:
    spec:
      sources:
        - chart: app-name
          repoURL: https://charts.example.com
          targetRevision: "{{.values.targetRevision}}"  # Templated version
          helm:
            valueFiles:
              - $values/argocd/upstream-app/values.yaml
```

**Supported formats:**
- Direct version: `targetRevision: "1.2.3"`
- Templated version: `targetRevision: "{{.values.targetRevision}}"`
- Git-based charts: `path: charts/app-name` (automatically skipped)

---

## Troubleshooting

### Hook Not Running

Check file patterns match your repository structure:

```bash
# List files that would trigger hooks
git ls-files | grep -E '\.(yaml|yml)$'
```

### Helm Dependency Errors

If you see "no repository definition" errors:

```bash
# Add required Helm repositories
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### yq Version Issues

Ensure you have go-yq (mikefarah/yq), not python-yq:

```bash
yq --version
# Should show: yq (https://github.com/mikefarah/yq/) version X.X.X
```

### Git-Based Charts

Git-based charts (using `path` instead of `chart` in ApplicationSets) are automatically skipped as they cannot be validated without cloning the repository.

---

## Running Hooks on Specific Files/Directories

Pre-commit hooks support multiple ways to target specific files and directories:

### Command-Line Options

```bash
# Run on specific files
pre-commit run --files argocd/grafana/values.yaml
pre-commit run --files argocd/grafana/Chart.yaml argocd/grafana/values.yaml

# Run on specific directories (using shell globbing)
pre-commit run --files argocd/grafana/*
pre-commit run --files argocd/*/values.yaml

# Run on all files matching a pattern
pre-commit run --files 'argocd/grafana/**/*'

# Run specific hook on specific files
pre-commit run helm-validate-custom-charts --files argocd/grafana/Chart.yaml

# Run only on staged files (default behavior)
pre-commit run

# Run on all files
pre-commit run --all-files
```

### Configuration-Based Filtering

Limit hooks to specific directories in `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      # Only validate grafana and mimir custom charts
      - id: helm-validate-custom-charts
        files: ^argocd/(grafana|mimir)/
      
      # Only validate loki values
      - id: helm-validate-values-only
        files: ^argocd/loki/
      
      # Validate all ApplicationSets (default behavior)
      - id: helm-validate-appsets
```

**Regex patterns for `files` parameter:**
- `^argocd/grafana/` - Only grafana directory
- `^argocd/(grafana|mimir)/` - Multiple specific directories
- `^argocd/.*/values\.yaml$` - All values.yaml files
- `^argocd/(?!mimir)` - All except mimir (negative lookahead)

### Exclude Specific Files

Exclude problematic files temporarily:

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main
    hooks:
      - id: helm-validate-custom-charts
        exclude: ^argocd/mimir/  # Skip mimir validation
```

### Built-in File Pattern Filtering

Each hook has built-in file patterns that automatically filter relevant files:

- **helm-template-all**: Runs on all `.yaml` and `.yml` files
- **helm-validate-custom-charts**: Only runs on `Chart.yaml` and `templates/*.yaml` files
- **helm-validate-values-only**: Only runs on `values.yaml` files
- **helm-validate-appsets**: Only runs on files in `argo-cd/appsets/`

These patterns ensure hooks only run when relevant files change.

### Practical Examples

**During development - test only your changes:**
```bash
# Test only the chart you're working on
pre-commit run --files argocd/grafana/*

# Test only values files you changed
pre-commit run helm-validate-values-only --files argocd/loki/values.yaml
```

**In CI - validate everything:**
```bash
# Run all hooks on all files
pre-commit run --all-files
```

**Temporarily skip problematic charts:**
```yaml
# In .pre-commit-config.yaml
- id: helm-validate-custom-charts
  exclude: ^argocd/(mimir|tempo)/  # Skip these until fixed
```

---

## Development

### Testing Locally

```bash
# Test in your repository
cd /path/to/your/repo
pre-commit run helm-template-all --all-files

# Test specific hooks
pre-commit run helm-validate-custom-charts --all-files
pre-commit run helm-validate-values-only --all-files
pre-commit run helm-validate-appsets --all-files

# Test on specific directories
pre-commit run --files argocd/grafana/*
pre-commit run --files argocd/loki/values.yaml
```

### Contributing

Contributions welcome! Please ensure:
- No company-specific or proprietary information
- Generic, reusable implementations
- Clear documentation
- Test coverage for new features

---

## License

MIT License - See LICENSE file for details

## Author

Nathan Gamber (ngamber)