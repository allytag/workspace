#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: jadx_readonly.sh [options]

Options:
  --apk PATH        APK to open (default: BASE/app.apk)
  --out-dir PATH    Output directory for decompiled sources (default: BASE/jadx_out)
  --threads N       Threads count for JADX (default: 2)
  --no-gradle       Skip Gradle project export fallback
  --keep            Keep existing output directory (skip deletion)
  -h, --help        Show this help
EOF
}

APK_PATH=""
DEFAULT_OUT_REL="work/jadx_out"
OUT_DIR=""
THREADS=2
EXPORT_GRADLE=true
KEEP_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk)
      [[ $# -ge 2 ]] || { log_error "--apk requires a path"; usage; }
      APK_PATH="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || { log_error "--out-dir requires a path"; usage; }
      OUT_DIR="$2"
      shift 2
      ;;
    --threads)
      [[ $# -ge 2 ]] || { log_error "--threads requires a value"; usage; }
      THREADS="$2"
      shift 2
      ;;
    --no-gradle)
      EXPORT_GRADLE=false
      shift
      ;;
    --keep)
      KEEP_OUTPUT=true
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

if [[ -z "$APK_PATH" ]]; then
  APK_PATH="$BASE_DIR/app.apk"
fi

if [[ -f "$APK_PATH" ]]; then
  APK_PATH="$(cd -- "$(dirname "$APK_PATH")" && pwd -P)/$(basename "$APK_PATH")"
else
  log_error "APK not found: $APK_PATH"
  exit 1
fi

CALLER_PWD="$(pwd -P)"

DEFAULT_OUT_DIR="$BASE_DIR/$DEFAULT_OUT_REL"
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="$DEFAULT_OUT_DIR"
  LEGACY_OUT="$BASE_DIR/jadx_out"
  if [[ -d "$LEGACY_OUT" && ! -d "$DEFAULT_OUT_DIR" ]]; then
    log_info "Migrating legacy JADX output from $LEGACY_OUT to $DEFAULT_OUT_DIR"
    ensure_dir "$WORK_DIR"
    mv "$LEGACY_OUT" "$DEFAULT_OUT_DIR"
  fi
fi

OUT_DIR="$(abs_path "$OUT_DIR" "$CALLER_PWD")"

JADX_BIN="$(find_jadx_cli)"

if ! $KEEP_OUTPUT && [[ -d "$OUT_DIR" ]]; then
  log_info "Clearing previous JADX output at $OUT_DIR"
  rm -rf "$OUT_DIR"
fi
ensure_dir "$OUT_DIR"

common_args=(
  --log-level ERROR
  --show-bad-code
  --deobf
  --deobf-min 2
  --rename-flags printable,valid
  --threads-count "$THREADS"
  -d "$OUT_DIR"
  "$APK_PATH"
)

run_jadx() {
  if $EXPORT_GRADLE; then
    log_info "Running JADX with Gradle export..."
    set +e
    "$JADX_BIN" --export-gradle "${common_args[@]}"
    local status=$?
    set -e
    if [[ $status -eq 0 ]]; then
      return 0
    fi
    log_warn "Gradle export failed (exit $status), retrying without --export-gradle."
    rm -rf "$OUT_DIR"
    ensure_dir "$OUT_DIR"
  fi

  log_info "Running JADX without Gradle export..."
  set +e
  "$JADX_BIN" "${common_args[@]}"
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    log_warn "JADX finished with exit status $status. Decompiled output is available, but review the warnings above."
  fi
  return 0
}

run_jadx

log_success "JADX output: $OUT_DIR"
log_info "For resource/smali editing, use: $WORK_DIR/decoded"
