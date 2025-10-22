#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: cleanup_all.sh [options]

Removes the entire workspace directory.

Options:
  --yes       Skip confirmation prompt.
  --dry-run   Show what would be removed without deleting anything.
  -h, --help  Show this help.
EOF
}

AUTO_YES=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      AUTO_YES=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unexpected argument: $1"
      usage
      exit 1
      ;;
  esac
done

TARGETS=("$BASE_DIR")

log_warn "The following paths will be removed:"
for path in "${TARGETS[@]}"; do
  echo " - $path"
done

if $DRY_RUN; then
  log_info "Dry run complete. Nothing deleted."
  exit 0
fi

if ! $AUTO_YES; then
  if ! confirm "Proceed? (y/N): "; then
    log_info "Aborted."
    exit 0
  fi
fi

for path in "${TARGETS[@]}"; do
  if [[ -e "$path" ]]; then
    log_warn "Removing $path"
    rm -rf "$path"
  fi
done

log_success "Workspace cleaned."
