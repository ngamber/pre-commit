#!/bin/bash
# helm-template-all.sh - Comprehensive Helm template validation
# Validates all Helm charts in the repository (custom charts, values-only charts, and ApplicationSets)

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

log_info "Starting comprehensive Helm validation"
log_info "Repository root: $REPO_ROOT"

# Track validation results
TOTAL_CHARTS=0
PASSED_CHARTS=0
FAILED_CHARTS=0
SKIPPED_CHARTS=0

# Validate all charts in argocd/ directory
log_info "Scanning for charts in argocd/ directory..."

while IFS= read -r chart_dir; do
    TOTAL_CHARTS=$((TOTAL_CHARTS + 1))
    chart_name=$(basename "$chart_dir")
    
    # Determine chart type and validate accordingly
    if is_custom_chart "$chart_dir"; then
        # Custom chart with Chart.yaml
        if validate_custom_chart "$chart_dir"; then
            PASSED_CHARTS=$((PASSED_CHARTS + 1))
        else
            FAILED_CHARTS=$((FAILED_CHARTS + 1))
        fi
        
    elif is_values_only_chart "$chart_dir"; then
        # Values-only chart - need to find ApplicationSet
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
        
    else
        log_warn "$chart_name: Unknown chart type, skipping"
        SKIPPED_CHARTS=$((SKIPPED_CHARTS + 1))
    fi
done < <(get_chart_directories "$REPO_ROOT")

# Validate ApplicationSets
log_info "Validating ApplicationSets..."

APPSET_COUNT=0
APPSET_PASSED=0
APPSET_FAILED=0

while IFS= read -r appset_file; do
    APPSET_COUNT=$((APPSET_COUNT + 1))
    
    if validate_appset_syntax "$appset_file"; then
        APPSET_PASSED=$((APPSET_PASSED + 1))
    else
        APPSET_FAILED=$((APPSET_FAILED + 1))
    fi
done < <(get_appset_files "$REPO_ROOT")

# Print summary
echo ""
log_info "=== Validation Summary ==="
log_info "Charts: $TOTAL_CHARTS total, $PASSED_CHARTS passed, $FAILED_CHARTS failed, $SKIPPED_CHARTS skipped"
log_info "ApplicationSets: $APPSET_COUNT total, $APPSET_PASSED passed, $APPSET_FAILED failed"

# Exit with error if any validations failed
if [ $FAILED_CHARTS -gt 0 ] || [ $APPSET_FAILED -gt 0 ]; then
    log_error "Validation failed!"
    exit 1
fi

log_success "All validations passed!"
exit 0