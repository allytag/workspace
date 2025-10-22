#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: decode.sh [options]

Options:
  --apk PATH     Decode a specific APK (defaults to BASE/app.apk).
  --open         Launch the decoded folder in VS Code after decoding.
  --no-open      (Deprecated) Present for backwards compatibility; no effect.
  --no-backup    Skip creating a tar.gz backup of the existing decode.
  -h, --help     Show this help.
EOF
}

APK_PATH=""
OPEN_IN_CODE=false
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk)
      [[ $# -ge 2 ]] || { log_error "--apk requires a path"; usage; }
      APK_PATH="$2"
      shift 2
      ;;
    --open)
      OPEN_IN_CODE=true
      shift
      ;;
    --no-open)
      # kept for backwards compatibility with older workflow scripts
      log_warn "--no-open is deprecated; decoding no longer launches VS Code automatically."
      shift
      ;;
    --no-backup)
      SKIP_BACKUP=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$APK_PATH" ]]; then
        APK_PATH="$1"
        shift
      else
        log_error "Unexpected argument: $1"
        usage
        exit 1
      fi
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

JAVA_BIN="$(detect_java)"
APKTOOL_JAR="$(find_apktool_jar)"
DECODED_DIR="$WORK_DIR/decoded"
FRAMEWORK_DIR="$WORK_DIR/apkfw"
BACKUP_DIR="$WORK_DIR/backups"

require_file "$APKTOOL_JAR"
ensure_dir "$WORK_DIR"
ensure_dir "$FRAMEWORK_DIR"

set +e
APKTOOL_VERSION_RAW="$("$JAVA_BIN" -jar "$APKTOOL_JAR" --version 2>/dev/null)"
status=$?
set -e
APKTOOL_VERSION=""
if [[ $status -eq 0 ]]; then
  APKTOOL_VERSION="$(printf '%s' "$APKTOOL_VERSION_RAW" | tr -d '\r\n')"
fi

USE_AAPT2_FLAG=true
if [[ -n "$APKTOOL_VERSION" ]]; then
  if version_ge "$APKTOOL_VERSION" "2.12.0"; then
    USE_AAPT2_FLAG=false
    log_info "apktool $APKTOOL_VERSION defaults to AAPT2; skipping --use-aapt2 flag."
  fi
else
  log_warn "Unable to detect apktool version; retaining legacy --use-aapt2 flag."
fi

if [[ -d "$DECODED_DIR" && -n "$(ls -A "$DECODED_DIR" 2>/dev/null)" ]]; then
  if ! $SKIP_BACKUP; then
    ensure_dir "$BACKUP_DIR"
    BACKUP_PATH="$BACKUP_DIR/decoded_$(timestamp).tar.gz"
    log_info "Backing up existing decode to $BACKUP_PATH"
    tar -C "$DECODED_DIR" -czf "$BACKUP_PATH" .
  else
    log_warn "Skipping backup of existing decode."
  fi
  rm -rf "$DECODED_DIR"
fi

log_info "Decoding $APK_PATH"
apktool_args=(
  d
  "$APK_PATH"
  -o "$DECODED_DIR"
  -p "$FRAMEWORK_DIR"
  -f
)
if $USE_AAPT2_FLAG; then
  apktool_args+=(--use-aapt2)
fi
"$JAVA_BIN" -jar "$APKTOOL_JAR" "${apktool_args[@]}"

if $OPEN_IN_CODE; then
  maybe_open_with_code "$DECODED_DIR"
fi

log_success "Decoded at: $DECODED_DIR"
