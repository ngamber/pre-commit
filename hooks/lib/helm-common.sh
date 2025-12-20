#!/bin/bash
# helm-common.sh - Shared library for Helm validation hooks
# This library provides common functions used across all Helm validation hooks

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_failure() {
    echo -e "${RED}✗${NC} $1"
}

# Check if required commands are available
check_dependencies() {
    local missing_deps=()
    
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install the missing dependencies and try again."
        return 1
    fi
    
    return 0
}

# Find the repository root directory
find_repo_root() {
    local current_dir="$PWD"
    
    while [ "$current_dir" != "/" ]; do
        if [ -d "$current_dir/.git" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    log_error "Could not find repository root (no .git directory found)"
    return 1
}

# Extract chart information from ApplicationSet file
# Returns: chart_name, repo_url, target_revision
extract_chart_info_from_appset() {
    local appset_file="$1"
    local chart_name=""
    local repo_url=""
    local target_revision=""
    
    if [ ! -f "$appset_file" ]; then
        log_error "ApplicationSet file not found: $appset_file"
        return 1
    fi
    
    # Try to extract chart field (Helm repository) - get first match only
    chart_name=$(yq eval '.spec.template.spec.sources[] | select(.chart != null) | .chart' "$appset_file" 2>/dev/null | head -n1 || echo "")
    
    # If no chart field, try path field (Git repository) - get first match only
    if [ -z "$chart_name" ]; then
        local chart_path
        chart_path=$(yq eval '.spec.template.spec.sources[] | select(.path != null) | .path' "$appset_file" 2>/dev/null | head -n1 || echo "")
        if [ -n "$chart_path" ]; then
            chart_name="git:${chart_path}"
        fi
    fi
    
    # Extract repository URL - get the one matching the chart/path
    if [[ "$chart_name" == git:* ]]; then
        # For git charts, get the repoURL that has a path field
        repo_url=$(yq eval '.spec.template.spec.sources[] | select(.path != null) | .repoURL' "$appset_file" 2>/dev/null | head -n1 || echo "")
    else
        # For Helm charts, get the repoURL that has a chart field
        repo_url=$(yq eval '.spec.template.spec.sources[] | select(.chart != null) | .repoURL' "$appset_file" 2>/dev/null | head -n1 || echo "")
    fi
    
    # Extract target revision - get the one matching the chart/path
    if [[ "$chart_name" == git:* ]]; then
        target_revision=$(yq eval '.spec.template.spec.sources[] | select(.path != null) | .targetRevision' "$appset_file" 2>/dev/null | head -n1 || echo "")
    else
        target_revision=$(yq eval '.spec.template.spec.sources[] | select(.chart != null) | .targetRevision' "$appset_file" 2>/dev/null | head -n1 || echo "")
    fi
    
    # Resolve templated versions from generators
    if [[ "$target_revision" == *"{{.values.targetRevision}}"* ]]; then
        local resolved_version
        resolved_version=$(yq eval '.spec.generators[0].clusters.values.targetRevision' "$appset_file" 2>/dev/null || echo "")
        if [ -n "$resolved_version" ]; then
            target_revision="${target_revision//\{\{.values.targetRevision\}\}/$resolved_version}"
        fi
    fi
    
    # Remove 'v' prefix if present
    target_revision="${target_revision#v}"
    
    # Export variables for caller
    echo "CHART_NAME=$chart_name"
    echo "REPO_URL=$repo_url"
    echo "TARGET_REVISION=$target_revision"
}

# Check if a chart is git-based
is_git_chart() {
    local chart_name="$1"
    [[ "$chart_name" == git:* ]]
}

# Find ApplicationSet file for a given chart directory
find_appset_for_chart() {
    local chart_dir="$1"
    local repo_root="$2"
    local chart_name
    
    chart_name=$(basename "$chart_dir")
    
    # Look for ApplicationSet in argo-cd/appsets/
    local appset_file="${repo_root}/argo-cd/appsets/${chart_name}/${chart_name}.yaml"
    
    if [ -f "$appset_file" ]; then
        echo "$appset_file"
        return 0
    fi
    
    # Alternative location
    appset_file="${repo_root}/argo-cd/appsets/${chart_name}.yaml"
    if [ -f "$appset_file" ]; then
        echo "$appset_file"
        return 0
    fi
    
    return 1
}

# Check if a directory is a custom Helm chart
is_custom_chart() {
    local dir="$1"
    [ -f "${dir}/Chart.yaml" ]
}

# Check if a directory is a values-only chart
is_values_only_chart() {
    local dir="$1"
    [ -f "${dir}/values.yaml" ] && [ ! -f "${dir}/Chart.yaml" ]
}

# Build Helm dependencies for a chart
build_helm_dependencies() {
    local chart_dir="$1"
    
    if [ ! -f "${chart_dir}/Chart.yaml" ]; then
        log_error "Chart.yaml not found in $chart_dir"
        return 1
    fi
    
    local has_dependencies
    has_dependencies=$(yq eval '.dependencies | length' "${chart_dir}/Chart.yaml" 2>/dev/null || echo "0")
    
    if [ "$has_dependencies" != "0" ] && [ "$has_dependencies" != "null" ]; then
        log_info "Building dependencies for $(basename "$chart_dir")..."
        if ! helm dependency build "$chart_dir" 2>&1; then
            log_error "Failed to build dependencies for $chart_dir"
            return 1
        fi
    fi
    
    return 0
}

# Validate a custom Helm chart
validate_custom_chart() {
    local chart_dir="$1"
    local chart_name
    chart_name=$(basename "$chart_dir")
    
    log_info "Validating custom chart: $chart_name"
    
    # Build dependencies if needed
    if ! build_helm_dependencies "$chart_dir"; then
        return 1
    fi
    
    # Run helm template
    if helm template test-release "$chart_dir" > /dev/null 2>&1; then
        log_success "$chart_name: Custom chart validation passed"
        return 0
    else
        log_failure "$chart_name: Custom chart validation failed"
        helm template test-release "$chart_dir" 2>&1 | sed 's/^/  /'
        return 1
    fi
}

# Validate a values-only chart
validate_values_only_chart() {
    local values_file="$1"
    local chart_name="$2"
    local repo_url="$3"
    local target_revision="$4"
    
    log_info "Validating values-only chart: $chart_name"
    
    # Skip git-based charts
    if is_git_chart "$chart_name"; then
        log_warn "$chart_name: Skipping validation (git-based chart)"
        return 0
    fi
    
    # Validate with upstream chart
    if helm template test-release "$chart_name" \
        --repo "$repo_url" \
        --version "$target_revision" \
        -f "$values_file" > /dev/null 2>&1; then
        log_success "$chart_name: Values-only chart validation passed"
        return 0
    else
        log_failure "$chart_name: Values-only chart validation failed"
        helm template test-release "$chart_name" \
            --repo "$repo_url" \
            --version "$target_revision" \
            -f "$values_file" 2>&1 | sed 's/^/  /'
        return 1
    fi
}

# Validate ApplicationSet YAML syntax
validate_appset_syntax() {
    local appset_file="$1"
    local appset_name
    appset_name=$(basename "$appset_file" .yaml)
    
    log_info "Validating ApplicationSet: $appset_name"
    
    # Check YAML syntax
    if ! yq eval '.' "$appset_file" > /dev/null 2>&1; then
        log_failure "$appset_name: Invalid YAML syntax"
        yq eval '.' "$appset_file" 2>&1 | sed 's/^/  /'
        return 1
    fi
    
    # Check for required fields
    local kind
    kind=$(yq eval '.kind' "$appset_file" 2>/dev/null || echo "")
    
    if [ "$kind" != "ApplicationSet" ]; then
        log_failure "$appset_name: Not an ApplicationSet (kind: $kind)"
        return 1
    fi
    
    log_success "$appset_name: ApplicationSet validation passed"
    return 0
}

# Get list of chart directories in repository
get_chart_directories() {
    local repo_root="$1"
    local argocd_dir="${repo_root}/argocd"
    
    if [ ! -d "$argocd_dir" ]; then
        log_error "ArgoCD directory not found: $argocd_dir"
        return 1
    fi
    
    find "$argocd_dir" -mindepth 1 -maxdepth 1 -type d
}

# Get list of ApplicationSet files in repository
get_appset_files() {
    local repo_root="$1"
    local appsets_pattern="${APPSETS_DIR_PATTERN:-argo-cd/appsets}"
    local appsets_dir="${repo_root}/${appsets_pattern}"
    
    if [ ! -d "$appsets_dir" ]; then
        log_error "ApplicationSets directory not found: $appsets_dir"
        return 1
    fi
    
    # Find all .yaml and .yml files recursively in the appsets directory
    # Filter to only include files that contain "kind: ApplicationSet"
    while IFS= read -r file; do
        if grep -q "kind: ApplicationSet" "$file" 2>/dev/null; then
            echo "$file"
        fi
    done < <(find "$appsets_dir" -type f \( -name "*.yaml" -o -name "*.yml" \))
}