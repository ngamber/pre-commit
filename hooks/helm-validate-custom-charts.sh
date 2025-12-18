#!/bin/bash
# helm-validate-custom-charts.sh - Validate custom Helm charts with Chart.yaml
# Only validates charts that have a Chart.yaml file (custom charts)

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common library
# shellcheck source=lib/helm-common.sh
source "${SCRIPT_DIR}/lib/helm-common.sh"

# Check dependencies
check_dependencies helm yq || exit 1

# Find repository root
REPO_ROOT=$(find_repo_root) || exit 1

log_info "Starting custom Helm chart validation"
log_info "Repository root: $REPO_ROOT"

# Track validation results
TOTAL_CHARTS=0
PASSED_CHARTS=0
FAILED_CHARTS=0

# Validate all custom charts in argocd/ directory
log_info "Scanning for custom charts in argocd/ directory..."

while IFS= read -r chart_dir; do
    chart_name=$(basename "$chart_dir")
    
    # Only process custom charts (with Chart.yaml)
    if ! is_custom_chart "$chart_dir"; then
        continue
    fi
    
    TOTAL_CHARTS=$((TOTAL_CHARTS + 1))
    
    if validate_custom_chart "$chart_dir"; then
        PASSED_CHARTS=$((PASSED_CHARTS + 1))
    else
        FAILED_CHARTS=$((FAILED_CHARTS + 1))
    fi
done < <(get_chart_directories "$REPO_ROOT")

# Print summary
echo ""
log_info "=== Custom Chart Validation Summary ==="
log_info "Total: $TOTAL_CHARTS, Passed: $PASSED_CHARTS, Failed: $FAILED_CHARTS"

# Exit with error if any validations failed
if [ $FAILED_CHARTS -gt 0 ]; then
    log_error "Custom chart validation failed!"
    exit 1
fi

if [ $TOTAL_CHARTS -eq 0 ]; then
    log_warn "No custom charts found to validate"
    exit 0
fi

log_success "All custom charts validated successfully!"
exit 0