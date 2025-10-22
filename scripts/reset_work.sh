#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: reset_work.sh [options]

Cleans build artifacts inside the workspace without touching tools or env files.

Removes by default:
  - work/decoded
  - work/backups
  - work/out
  - work/unsigned.apk
  - work/jadx_out

Options:
  --keep-backups    Preserve work/backups (keeps historical tarballs).
  --keep-jadx       Preserve work/jadx_out.
  --reset-framework Also delete work/apkfw (apktool framework cache).
  --yes             Skip confirmation prompt.
  --dry-run         Show what would be removed without deleting anything.
  -h, --help        Show this help.
EOF
}

KEEP_BACKUPS=false
KEEP_JADX=false
RESET_FRAMEWORK=false
AUTO_YES=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-backups)
      KEEP_BACKUPS=true
      shift
      ;;
    --keep-jadx)
      KEEP_JADX=true
      shift
      ;;
    --reset-framework)
      RESET_FRAMEWORK=true
      shift
      ;;
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

ensure_dir "$WORK_DIR"

declare -a TARGETS=()
declare -a SKIPPED=()

decoded_dir="$WORK_DIR/decoded"
[[ -d "$decoded_dir" ]] && TARGETS+=("$decoded_dir")

backups_dir="$WORK_DIR/backups"
if [[ -d "$backups_dir" ]]; then
  if $KEEP_BACKUPS; then
    SKIPPED+=("$backups_dir (kept)")
  else
    TARGETS+=("$backups_dir")
  fi
fi

out_dir="$WORK_DIR/out"
[[ -d "$out_dir" ]] && TARGETS+=("$out_dir")

unsigned_apk="$WORK_DIR/unsigned.apk"
[[ -f "$unsigned_apk" ]] && TARGETS+=("$unsigned_apk")

jadx_dir="$WORK_DIR/jadx_out"
if [[ -d "$jadx_dir" ]]; then
  if $KEEP_JADX; then
    SKIPPED+=("$jadx_dir (kept)")
  else
    TARGETS+=("$jadx_dir")
  fi
fi

if $RESET_FRAMEWORK; then
  framework_dir="$WORK_DIR/apkfw"
  [[ -d "$framework_dir" ]] && TARGETS+=("$framework_dir")
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  log_info "Nothing to clean. Workspace already fresh."
  exit 0
fi

log_info "The following will be removed:"
for path in "${TARGETS[@]}"; do
  echo " - $path"
done
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
  log_info "Preserving:"
  for path in "${SKIPPED[@]}"; do
    echo " - $path"
  done
fi

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
    log_info "Removing $path"
    rm -rf "$path"
  fi
done

log_success "Workspace reset complete. Ready for a new APK."
