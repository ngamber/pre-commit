#!/bin/bash
# helm-validate-appsets.sh - Validate ApplicationSet YAML files
# Validates ApplicationSet syntax and structure

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common library
# shellcheck source=lib/helm-common.sh
source "${SCRIPT_DIR}/lib/helm-common.sh"

# Check dependencies
check_dependencies yq || exit 1

# Find repository root
REPO_ROOT=$(find_repo_root) || exit 1

log_info "Starting ApplicationSet validation"
log_info "Repository root: $REPO_ROOT"

# Track validation results
TOTAL_APPSETS=0
PASSED_APPSETS=0
FAILED_APPSETS=0

# Validate all ApplicationSets
log_info "Scanning for ApplicationSets in argo-cd/appsets/ directory..."

while IFS= read -r appset_file; do
    TOTAL_APPSETS=$((TOTAL_APPSETS + 1))
    
    if validate_appset_syntax "$appset_file"; then
        PASSED_APPSETS=$((PASSED_APPSETS + 1))
    else
        FAILED_APPSETS=$((FAILED_APPSETS + 1))
    fi
done < <(get_appset_files "$REPO_ROOT")

# Print summary
echo ""
log_info "=== ApplicationSet Validation Summary ==="
log_info "Total: $TOTAL_APPSETS, Passed: $PASSED_APPSETS, Failed: $FAILED_APPSETS"

# Exit with error if any validations failed
if [ $FAILED_APPSETS -gt 0 ]; then
    log_error "ApplicationSet validation failed!"
    exit 1
fi

if [ $TOTAL_APPSETS -eq 0 ]; then
    log_warn "No ApplicationSets found to validate"
    exit 0
fi

log_success "All ApplicationSets validated successfully!"
exit 0