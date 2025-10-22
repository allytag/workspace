#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: rebuild_and_sign.sh [options]

Options:
  --out-dir PATH     Output directory for signed APKs (default: work/out)
  --unsigned PATH    Location for the temporary unsigned APK (default: work/unsigned.apk)
  --keystore PATH    Use/create this keystore (default: work/release.jks)
  --alias NAME       Keystore alias (default: release)
  --storepass PASS   Keystore password (default: releasepass)
  --keypass PASS     Key password (default: same as storepass)
  --skip-verify      Skip APK signature verification step
  --fresh            Clean output directory before signing
  -h, --help         Show this help
EOF
}

OUT_DIR="$WORK_DIR/out"
UNSIGNED_APK="$WORK_DIR/unsigned.apk"
KS_PATH="$WORK_DIR/release.jks"
KS_ALIAS="release"
KS_PASS="releasepass"
KS_KEY_PASS=""
SKIP_VERIFY=false
CLEAN_OUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || { log_error "--out-dir requires a path"; usage; }
      OUT_DIR="$2"
      shift 2
      ;;
    --unsigned)
      [[ $# -ge 2 ]] || { log_error "--unsigned requires a path"; usage; }
      UNSIGNED_APK="$2"
      shift 2
      ;;
    --keystore)
      [[ $# -ge 2 ]] || { log_error "--keystore requires a path"; usage; }
      KS_PATH="$2"
      shift 2
      ;;
    --alias)
      [[ $# -ge 2 ]] || { log_error "--alias requires a value"; usage; }
      KS_ALIAS="$2"
      shift 2
      ;;
    --storepass)
      [[ $# -ge 2 ]] || { log_error "--storepass requires a value"; usage; }
      KS_PASS="$2"
      shift 2
      ;;
    --keypass)
      [[ $# -ge 2 ]] || { log_error "--keypass requires a value"; usage; }
      KS_KEY_PASS="$2"
      shift 2
      ;;
    --skip-verify)
      SKIP_VERIFY=true
      shift
      ;;
    --fresh)
      CLEAN_OUT=true
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

[[ -n "$KS_KEY_PASS" ]] || KS_KEY_PASS="$KS_PASS"

CALLER_PWD="$(pwd -P)"

DECODED_DIR="$WORK_DIR/decoded"
FRAMEWORK_DIR="$WORK_DIR/apkfw"
require_dir "$DECODED_DIR"
ensure_dir "$FRAMEWORK_DIR"

JAVA_BIN="$(detect_java)"
KEYTOOL_BIN="$(detect_keytool)"
APKTOOL_JAR="$(find_apktool_jar)"
UBER_JAR="$(find_uber_apk_signer)"
require_file "$APKTOOL_JAR"
require_file "$UBER_JAR"

set +e
UBER_HELP_OUTPUT="$("$JAVA_BIN" -jar "$UBER_JAR" --help 2>/dev/null)"
UBER_HELP_STATUS=$?
UBER_VERSION_RAW="$("$JAVA_BIN" -jar "$UBER_JAR" -v 2>/dev/null)"
UBER_VERSION_STATUS=$?
set -e
UBER_SUPPORTS_APKSIGNER_ARGS=false
UBER_SUPPORTS_ONLY_VERIFY=false
UBER_VERSION=""
if [[ $UBER_HELP_STATUS -eq 0 ]]; then
  if grep -q -- '--apksigner-args' <<< "$UBER_HELP_OUTPUT"; then
    UBER_SUPPORTS_APKSIGNER_ARGS=true
  fi
  if grep -q -- '-y,--onlyVerify' <<< "$UBER_HELP_OUTPUT"; then
    UBER_SUPPORTS_ONLY_VERIFY=true
  fi
fi
if [[ $UBER_VERSION_STATUS -eq 0 ]]; then
  UBER_VERSION="$(extract_version_from_path "$UBER_VERSION_RAW")"
fi

UNSIGNED_APK="$(abs_path "$UNSIGNED_APK" "$CALLER_PWD")"
KS_PATH="$(abs_path "$KS_PATH" "$CALLER_PWD")"
OUT_DIR="$(abs_path "$OUT_DIR" "$CALLER_PWD")"

ensure_dir "$(dirname "$UNSIGNED_APK")"
ensure_dir "$(dirname "$KS_PATH")"

if $CLEAN_OUT && [[ -d "$OUT_DIR" ]]; then
  log_info "Cleaning output directory: $OUT_DIR"
  rm -rf "$OUT_DIR"
fi
ensure_dir "$OUT_DIR"

log_info "Building unsigned APK..."
rm -f "$UNSIGNED_APK"
apktool_build_args=(
  b
  "$DECODED_DIR"
  -o "$UNSIGNED_APK"
  -p "$FRAMEWORK_DIR"
)
"$JAVA_BIN" -jar "$APKTOOL_JAR" "${apktool_build_args[@]}"

if [[ ! -f "$KS_PATH" ]]; then
  log_info "Generating release keystore at $KS_PATH"
  "$KEYTOOL_BIN" -genkeypair -v \
    -keystore "$KS_PATH" \
    -storepass "$KS_PASS" \
    -keypass "$KS_KEY_PASS" \
    -alias "$KS_ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 36500 \
    -dname "CN=Mark, OU=Dev, O=Self, L=City, S=State, C=US"
else
  log_info "Using existing keystore: $KS_PATH"
fi

log_info "Signing APK..."
rm -f "$OUT_DIR"/*signed.apk
uber_sign_args=(
  -a "$UNSIGNED_APK"
  --ks "$KS_PATH"
  --ksAlias "$KS_ALIAS"
  --ksPass "$KS_PASS"
  --ksKeyPass "$KS_KEY_PASS"
  --out "$OUT_DIR"
)
if $UBER_SUPPORTS_APKSIGNER_ARGS; then
  uber_sign_args+=(--apksigner-args --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true)
else
  if [[ -n "$UBER_VERSION" ]]; then
    log_info "uber-apk-signer $UBER_VERSION lacks --apksigner-args; relying on default signing schemes."
  else
    log_info "uber-apk-signer lacks --apksigner-args; relying on default signing schemes."
  fi
fi
"$JAVA_BIN" -jar "$UBER_JAR" "${uber_sign_args[@]}"

set +e
SIGNED_APK="$(ls -t "$OUT_DIR"/*signed.apk 2>/dev/null | head -n1)"
set -e
if [[ -z "$SIGNED_APK" ]]; then
  log_error "Signed APK not found in $OUT_DIR"
  exit 1
fi

if ! $SKIP_VERIFY; then
  log_info "Verifying signed APK..."
  if $UBER_SUPPORTS_ONLY_VERIFY; then
    "$JAVA_BIN" -jar "$UBER_JAR" -y -a "$SIGNED_APK"
  else
    "$JAVA_BIN" -jar "$UBER_JAR" --verify -a "$SIGNED_APK"
  fi
fi

log_success "Signed APK ready: $SIGNED_APK"

if adb_path="$(detect_adb --optional)"; then
  log_info "Install command:"
  echo "  \"$adb_path\" install -r \"$SIGNED_APK\""
else
  log_warn "adb not found. Install Android Platform Tools to push the APK."
fi
