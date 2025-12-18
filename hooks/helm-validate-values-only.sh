#!/bin/bash
# helm-validate-values-only.sh - Validate values-only charts
# Only validates charts that have values.yaml but no Chart.yaml (values-only charts)

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

log_info "Starting values-only chart validation"
log_info "Repository root: $REPO_ROOT"

# Track validation results
TOTAL_CHARTS=0
PASSED_CHARTS=0
FAILED_CHARTS=0
SKIPPED_CHARTS=0

# Validate all values-only charts in argocd/ directory
log_info "Scanning for values-only charts in argocd/ directory..."

while IFS= read -r chart_dir; do
    chart_name=$(basename "$chart_dir")
    
    # Only process values-only charts (values.yaml but no Chart.yaml)
    if ! is_values_only_chart "$chart_dir"; then
        continue
    fi
    
    TOTAL_CHARTS=$((TOTAL_CHARTS + 1))
    
    # Find ApplicationSet for this chart
    appset_file=$(find_appset_for_chart "$chart_dir" "$REPO_ROOT") || {
        log_warn "$chart_name: No ApplicationSet found, skipping validation"
        SKIPPED_CHARTS=$((SKIPPED_CHARTS + 1))
        continue
    }
    
    # Extract chart info from ApplicationSet
    eval "$(extract_chart_info_from_appset "$appset_file")"
    
    # Skip git-based charts
    if is_git_chart "$CHART_NAME"; then
        log_warn "$chart_name: Skipping validation (git-based chart)"
        SKIPPED_CHARTS=$((SKIPPED_CHARTS + 1))
        continue
    fi
    
    # Validate values-only chart
    if validate_values_only_chart "${chart_dir}/values.yaml" "$CHART_NAME" "$REPO_URL" "$TARGET_REVISION"; then
        PASSED_CHARTS=$((PASSED_CHARTS + 1))
    else
        FAILED_CHARTS=$((FAILED_CHARTS + 1))
    fi
done < <(get_chart_directories "$REPO_ROOT")

# Print summary
echo ""
log_info "=== Values-Only Chart Validation Summary ==="
log_info "Total: $TOTAL_CHARTS, Passed: $PASSED_CHARTS, Failed: $FAILED_CHARTS, Skipped: $SKIPPED_CHARTS"

# Exit with error if any validations failed
if [ $FAILED_CHARTS -gt 0 ]; then
    log_error "Values-only chart validation failed!"
    exit 1
fi

if [ $TOTAL_CHARTS -eq 0 ]; then
    log_warn "No values-only charts found to validate"
    exit 0
fi

log_success "All values-only charts validated successfully!"
exit 0