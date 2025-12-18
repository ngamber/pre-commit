# Pre-commit Hooks for Kubernetes and Helm

A collection of pre-commit hooks for validating Kubernetes manifests and Helm charts.

## Available Hooks

### helm-template-validate

Validates Helm charts by running `helm template` to ensure templates render correctly. Supports both:
- **Custom charts** with `Chart.yaml` and templates
- **Values-only directories** that reference upstream Helm charts via ArgoCD ApplicationSets

#### Features

- Automatically detects chart type (custom vs values-only)
- Parses ArgoCD ApplicationSet files to extract upstream chart information
- Validates custom charts with `helm template`
- Validates values-only charts by adding upstream repo and templating with values file
- Configurable paths for chart directories and ApplicationSet files
- Detailed error reporting

#### Usage

Add to your `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/ngamber/pre-commit
    rev: main # Use the latest release
    hooks:
      - id: helm-template-validate
        args:
          - --chart-dirs=argocd
          - --appset-dir=argo-cd/appsets
```

#### Arguments

- `--chart-dirs`: Comma-separated list of directories containing Helm charts (default: `argocd`)
- `--appset-dir`: Directory containing ArgoCD ApplicationSet files (default: `argo-cd/appsets`)

#### Requirements

- `helm` CLI tool installed
- `yq` (YAML processor) installed for parsing ApplicationSet files
- For values-only charts: ApplicationSet files must follow standard ArgoCD format with `spec.template.spec.sources[]` containing `chart`, `repoURL`, and `targetRevision`

#### How It Works

1. **Chart Detection**: Checks each directory for `Chart.yaml`
   - If present: Treats as custom chart
   - If absent but `values.yaml` exists: Treats as values-only chart

2. **Custom Chart Validation**:
   ```bash
   helm template test-release /path/to/chart
   ```

3. **Values-Only Chart Validation**:
   - Parses corresponding ApplicationSet file to extract:
     - Chart name
     - Repository URL
     - Chart version
   - Adds Helm repository
   - Templates with values file:
   ```bash
   helm template test-release CHART_NAME --repo REPO_URL --version VERSION -f values.yaml
   ```

#### Example Repository Structure

```
your-repo/
├── argocd/                    # Chart directories
│   ├── custom-app/           # Custom chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── upstream-app/         # Values-only
│       └── values.yaml
└── argo-cd/
    └── appsets/              # ApplicationSet definitions
        └── upstream-app/
            └── upstream-app.yaml
```

#### ApplicationSet Format

For values-only charts, the ApplicationSet must contain chart information:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: upstream-app
spec:
  template:
    spec:
      sources:
        - chart: app-name
          repoURL: https://charts.example.com
          targetRevision: "1.2.3"
          helm:
            valueFiles:
              - $values/argocd/upstream-app/values.yaml
```

## Installation

### Prerequisites

```bash
# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install yq
brew install yq  # macOS
# or
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

### Add to Your Project

1. Install pre-commit:
   ```bash
   pip install pre-commit
   ```

2. Create `.pre-commit-config.yaml` in your repository:
   ```yaml
   repos:
     - repo: https://github.com/ngamber/pre-commit
       rev: v1.0.0
       hooks:
         - id: helm-template-validate
   ```

3. Install the hooks:
   ```bash
   pre-commit install
   ```

## Development

### Testing Locally

To test the hook locally before committing:

```bash
pre-commit run helm-template-validate --all-files
```

### Contributing

Contributions are welcome! Please ensure:
- No company-specific or proprietary information
- Generic, reusable implementations
- Clear documentation
- Test coverage for new features

## License

MIT License - See LICENSE file for details

## Author

Nathan Gamber (ngamber)