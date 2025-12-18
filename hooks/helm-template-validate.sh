#!/usr/bin/env bash

set -euo pipefail

# Default configuration
CHART_DIRS="${CHART_DIRS:-argocd}"
APPSET_DIR="${APPSET_DIR:-argo-cd/appsets}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --chart-dirs=*)
            CHART_DIRS="${1#*=}"
            shift
            ;;
        --appset-dir=*)
            APPSET_DIR="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check required tools
check_requirements() {
    local missing_tools=()
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required tools: ${missing_tools[*]}${NC}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

# Find ApplicationSet file for a chart
find_appset_file() {
    local chart_name="$1"
    local appset_file="${APPSET_DIR}/${chart_name}/${chart_name}.yaml"
    
    if [ -f "$appset_file" ]; then
        echo "$appset_file"
        return 0
    fi
    
    return 1
}

# Extract chart info from ApplicationSet
extract_chart_info() {
    local appset_file="$1"
    local chart_name repo_url target_revision chart_path
    
    # Parse ApplicationSet to extract chart information
    # First try to find a source with a chart field (Helm repository)
    chart_name=$(yq eval '.spec.template.spec.sources[] | select(.chart != null) | .chart' "$appset_file" | head -n1)
    repo_url=$(yq eval '.spec.template.spec.sources[] | select(.chart != null) | .repoURL' "$appset_file" | head -n1)
    target_revision=$(yq eval '.spec.template.spec.sources[] | select(.chart != null) | .targetRevision' "$appset_file" | head -n1)
    
    # If no chart field found, try path field (Git repository with chart path)
    if [ -z "$chart_name" ] || [ "$chart_name" == "null" ]; then
        chart_path=$(yq eval '.spec.template.spec.sources[] | select(.path != null) | .path' "$appset_file" | head -n1)
        repo_url=$(yq eval '.spec.template.spec.sources[] | select(.path != null) | .repoURL' "$appset_file" | head -n1)
        target_revision=$(yq eval '.spec.template.spec.sources[] | select(.path != null) | .targetRevision' "$appset_file" | head -n1)
        
        if [ -n "$chart_path" ] && [ "$chart_path" != "null" ]; then
            # Extract chart name from path (e.g., "charts/karpenter" -> "karpenter")
            chart_name=$(basename "$chart_path")
            # Mark this as a git-based chart
            chart_name="git:${chart_name}"
        fi
    fi
    
    # If targetRevision contains a template variable, try to resolve it from generators
    if [[ "$target_revision" == *"{{.values.targetRevision}}"* ]] || [[ "$target_revision" == *"v{{.values.targetRevision}}"* ]]; then
        # Try to extract from the first generator's values
        local resolved_version
        resolved_version=$(yq eval '.spec.generators[0].clusters.values.targetRevision' "$appset_file" 2>/dev/null)
        
        # If that didn't work, try other generator types
        if [ -z "$resolved_version" ] || [ "$resolved_version" == "null" ]; then
            resolved_version=$(yq eval '.spec.generators[0].list.elements[0].targetRevision' "$appset_file" 2>/dev/null)
        fi
        
        # If still no version found, return error
        if [ -z "$resolved_version" ] || [ "$resolved_version" == "null" ]; then
            return 1
        fi
        
        # Replace the template variable with the actual version
        target_revision="${target_revision//\{\{.values.targetRevision\}\}/$resolved_version}"
    fi
    
    if [ -z "$chart_name" ] || [ -z "$repo_url" ] || [ -z "$target_revision" ]; then
        return 1
    fi
    
    echo "$chart_name|$repo_url|$target_revision"
    return 0
}

# Validate a custom chart (has Chart.yaml)
validate_custom_chart() {
    local chart_dir="$1"
    local chart_name=$(basename "$chart_dir")
    
    echo -e "${YELLOW}Validating custom chart: ${chart_name}${NC}"
    
    # Check if chart has dependencies and build them if needed
    if [ -f "${chart_dir}/Chart.yaml" ]; then
        local has_dependencies
        has_dependencies=$(yq eval '.dependencies | length' "${chart_dir}/Chart.yaml" 2>/dev/null)
        
        if [ -n "$has_dependencies" ] && [ "$has_dependencies" != "0" ] && [ "$has_dependencies" != "null" ]; then
            echo "  Building chart dependencies..."
            if ! helm dependency build "$chart_dir" > /dev/null 2>&1; then
                echo -e "${RED}✗ ${chart_name}: Failed to build dependencies${NC}"
                helm dependency build "$chart_dir" 2>&1 || true
                return 1
            fi
        fi
    fi
    
    if helm template test-release "$chart_dir" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ ${chart_name}: Valid${NC}"
        return 0
    else
        echo -e "${RED}✗ ${chart_name}: Failed validation${NC}"
        echo "Running helm template for details:"
        helm template test-release "$chart_dir" 2>&1 || true
        return 1
    fi
}

# Validate a values-only chart (no Chart.yaml, has values.yaml)
validate_values_only_chart() {
    local chart_dir="$1"
    local chart_name=$(basename "$chart_dir")
    local values_file="${chart_dir}/values.yaml"
    
    echo -e "${YELLOW}Validating values-only chart: ${chart_name}${NC}"
    
    # Find corresponding ApplicationSet
    local appset_file
    if ! appset_file=$(find_appset_file "$chart_name"); then
        echo -e "${RED}✗ ${chart_name}: Could not find ApplicationSet file${NC}"
        echo "Expected: ${APPSET_DIR}/${chart_name}/${chart_name}.yaml"
        return 1
    fi
    
    # Extract chart information
    local chart_info
    if ! chart_info=$(extract_chart_info "$appset_file"); then
        echo -e "${RED}✗ ${chart_name}: Could not extract chart info from ApplicationSet${NC}"
        echo "ApplicationSet file: $appset_file"
        return 1
    fi
    
    IFS='|' read -r upstream_chart repo_url target_revision <<< "$chart_info"
    
    # Check if this is a git-based chart (starts with "git:")
    if [[ "$upstream_chart" == git:* ]]; then
        echo -e "${YELLOW}  Skipping validation: Git-based chart (not from Helm repository)${NC}"
        echo "  Chart path: ${upstream_chart#git:}"
        echo "  Repo: $repo_url"
        echo "  Version: $target_revision"
        return 0
    fi
    
    echo "  Chart: $upstream_chart"
    echo "  Repo: $repo_url"
    echo "  Version: $target_revision"
    
    # Generate a unique repo name to avoid conflicts
    local repo_name="precommit-${chart_name}-$(echo "$repo_url" | md5sum | cut -d' ' -f1 | cut -c1-8)"
    
    # Add helm repository (suppress output, ignore if already exists)
    if ! helm repo add "$repo_name" "$repo_url" &> /dev/null; then
        # Repo might already exist, try to update it
        helm repo update "$repo_name" &> /dev/null || true
    fi
    
    # Validate with helm template
    if helm template test-release "$upstream_chart" \
        --repo "$repo_url" \
        --version "$target_revision" \
        -f "$values_file" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ ${chart_name}: Valid${NC}"
        # Clean up repo
        helm repo remove "$repo_name" &> /dev/null || true
        return 0
    else
        echo -e "${RED}✗ ${chart_name}: Failed validation${NC}"
        echo "Running helm template for details:"
        helm template test-release "$upstream_chart" \
            --repo "$repo_url" \
            --version "$target_revision" \
            -f "$values_file" 2>&1 || true
        # Clean up repo
        helm repo remove "$repo_name" &> /dev/null || true
        return 1
    fi
}

# Main validation logic
validate_charts() {
    local exit_code=0
    local chart_dirs_array
    
    # Split comma-separated chart directories
    IFS=',' read -ra chart_dirs_array <<< "$CHART_DIRS"
    
    for base_dir in "${chart_dirs_array[@]}"; do
        # Trim whitespace
        base_dir=$(echo "$base_dir" | xargs)
        
        if [ ! -d "$base_dir" ]; then
            echo -e "${YELLOW}Warning: Chart directory not found: ${base_dir}${NC}"
            continue
        fi
        
        # Find all potential chart directories (directories with values.yaml or Chart.yaml)
        while IFS= read -r -d '' chart_dir; do
            chart_dir=$(dirname "$chart_dir")
            
            if [ -f "${chart_dir}/Chart.yaml" ]; then
                # Custom chart with Chart.yaml
                if ! validate_custom_chart "$chart_dir"; then
                    exit_code=1
                fi
            elif [ -f "${chart_dir}/values.yaml" ]; then
                # Values-only chart
                if ! validate_values_only_chart "$chart_dir"; then
                    exit_code=1
                fi
            fi
        done < <(find "$base_dir" -maxdepth 2 -type f \( -name "Chart.yaml" -o -name "values.yaml" \) -print0)
    done
    
    return $exit_code
}

# Main execution
main() {
    echo "=== Helm Template Validation ==="
    echo "Chart directories: $CHART_DIRS"
    echo "ApplicationSet directory: $APPSET_DIR"
    echo ""
    
    check_requirements
    
    if validate_charts; then
        echo ""
        echo -e "${GREEN}All charts validated successfully!${NC}"
        exit 0
    else
        echo ""
        echo -e "${RED}Some charts failed validation${NC}"
        exit 1
    fi
}

main "$@"