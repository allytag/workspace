#!/usr/bin/env bash
# Shared helpers for APK workflow scripts.

if [[ -z "${__APK_WORKFLOW_LIB_SOURCED:-}" ]]; then
  __APK_WORKFLOW_LIB_SOURCED=1

  # Resolve project paths relative to the scripts directory.
  SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
  WORK_DIR="$BASE_DIR/work"
  TOOLS_DIR="$BASE_DIR/tools"

  # shellcheck disable=SC1091
  if [[ -f "$WORK_DIR/env.sh" ]]; then
    source "$WORK_DIR/env.sh"
    if [[ -n "${JAVA_HOME:-}" ]]; then
      if [[ "$JAVA_HOME" != /* ]]; then
        JAVA_HOME="$BASE_DIR/$JAVA_HOME"
        export JAVA_HOME
      fi
      case ":$PATH:" in
        *":$JAVA_HOME/bin:"*) ;;
        *) PATH="$JAVA_HOME/bin:$PATH"; export PATH ;;
      esac
    fi
  fi

  find_bundled_java_home() {
    local candidate
    shopt -s nullglob
    for candidate in \
      "$TOOLS_DIR"/jdk*/Contents/Home \
      "$TOOLS_DIR"/jdk*/Home \
      "$TOOLS_DIR"/jdk* \
      "$TOOLS_DIR"/jre*/Contents/Home \
      "$TOOLS_DIR"/jre*/Home \
      "$TOOLS_DIR"/jre* \
      "$TOOLS_DIR"/java*/Contents/Home \
      "$TOOLS_DIR"/java*/Home \
      "$TOOLS_DIR"/java*; do
      if [[ -x "$candidate/bin/java" ]]; then
        (cd "$candidate" && pwd -P)
        shopt -u nullglob
        return 0
      fi
    done
    shopt -u nullglob
    return 1
  }

  if [[ -z "${JAVA_HOME:-}" ]]; then
    if bundled_java_home="$(find_bundled_java_home 2>/dev/null)"; then
      JAVA_HOME="$bundled_java_home"
      export JAVA_HOME
      case ":$PATH:" in
        *":$JAVA_HOME/bin:"*) ;;
        *) PATH="$JAVA_HOME/bin:$PATH"; export PATH ;;
      esac
    fi
  fi

  log_info()   { printf 'ℹ️  %s\n' "$*"; }
  log_success(){ printf '✅ %s\n' "$*"; }
  log_warn()   { printf '⚠️ %s\n' "$*"; }
  log_error()  { printf '❌ %s\n' "$*"; }

  require_file() {
    local path="$1"
    [[ -f "$path" ]] || { log_error "Missing file: $path"; exit 1; }
  }

  require_dir() {
    local path="$1"
    [[ -d "$path" ]] || { log_error "Missing directory: $path"; exit 1; }
  }

  ensure_dir() {
    local path="$1"
    mkdir -p "$path"
  }

  abs_path() {
    local target="$1"
    local base="${2:-$(pwd -P)}"
    if [[ "$target" == /* ]]; then
      printf '%s\n' "$target"
    else
      printf '%s\n' "$base/$target"
    fi
  }

  detect_java() {
    if [[ -n "${JAVA_BIN:-}" && -x "$JAVA_BIN" ]]; then
      echo "$JAVA_BIN"
      return
    fi
    if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
      echo "$JAVA_HOME/bin/java"
      return
    fi
    if command -v java >/dev/null 2>&1; then
      command -v java
      return
    fi
    log_error "Java runtime not found. Set JAVA_HOME in $WORK_DIR/env.sh."
    exit 1
  }

  detect_keytool() {
    if [[ -n "${KEYTOOL_BIN:-}" && -x "$KEYTOOL_BIN" ]]; then
      echo "$KEYTOOL_BIN"
      return
    fi
    if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/keytool" ]]; then
      echo "$JAVA_HOME/bin/keytool"
      return
    fi
    if command -v keytool >/dev/null 2>&1; then
      command -v keytool
      return
    fi
    log_error "keytool not found. Install JDK or adjust JAVA_HOME."
    exit 1
  }

  detect_adb() {
    local optional=false
    if [[ "${1:-}" == "--optional" ]]; then
      optional=true
      shift || true
    fi
    local bundled="$TOOLS_DIR/platform-tools/adb"
    if [[ -x "$bundled" ]]; then
      echo "$bundled"
      return
    fi
    if command -v adb >/dev/null 2>&1; then
      command -v adb
      return
    fi
    if $optional; then
      return 1
    fi
    log_error "adb executable not found. Download Platform Tools into $TOOLS_DIR/platform-tools."
    exit 1
  }

  extract_version_from_path() {
    local path="$1"
    local version
    version="$(printf '%s\n' "$path" | grep -Eo '([0-9]+([.][0-9]+)*)' | tail -n1 || true)"
    if [[ -z "$version" ]]; then
      version="0"
    fi
    printf '%s\n' "$version"
  }

  version_gt() {
    local a="$1"
    local b="$2"
    local IFS='.'
    read -ra A_PARTS <<< "$a"
    read -ra B_PARTS <<< "$b"
    local max_len="${#A_PARTS[@]}"
    if [[ ${#B_PARTS[@]} -gt $max_len ]]; then
      max_len="${#B_PARTS[@]}"
    fi
    for ((i = 0; i < max_len; i++)); do
      local av="${A_PARTS[i]:-0}"
      local bv="${B_PARTS[i]:-0}"
      if (( av > bv )); then
        return 0
      elif (( av < bv )); then
        return 1
      fi
    done
    return 1
  }

  version_ge() {
    local a="$1"
    local b="$2"
    if [[ "$a" == "$b" ]]; then
      return 0
    fi
    if version_gt "$a" "$b"; then
      return 0
    fi
    return 1
  }

  find_latest_glob() {
    local pattern="$1"
    local -a matches=()
    while IFS= read -r match; do
      matches+=("$match")
    done < <(compgen -G "$pattern")
    [[ ${#matches[@]} -gt 0 ]] || return 1
    local latest=""
    local latest_version="0"
    local candidate version
    for candidate in "${matches[@]}"; do
      version="$(extract_version_from_path "$candidate")"
      if [[ -z "$latest" ]]; then
        latest="$candidate"
        latest_version="$version"
        continue
      fi
      if version_gt "$version" "$latest_version"; then
        latest="$candidate"
        latest_version="$version"
      fi
    done
    printf '%s\n' "$latest"
  }

  find_apktool_jar() {
    local default="$TOOLS_DIR/apktool.jar"
    if [[ -f "$default" ]]; then
      printf '%s\n' "$default"
      return 0
    fi
    local pattern="$TOOLS_DIR"/apktool*.jar
    local latest
    if latest="$(find_latest_glob "$pattern" 2>/dev/null)"; then
      printf '%s\n' "$latest"
      return 0
    fi
    log_error "apktool JAR not found in $TOOLS_DIR. Place apktool.jar or apktool_*.jar there."
    exit 1
  }

  find_uber_apk_signer() {
    local default="$TOOLS_DIR/uber-apk-signer.jar"
    if [[ -f "$default" ]]; then
      printf '%s\n' "$default"
      return 0
    fi
    local pattern="$TOOLS_DIR"/uber-apk-signer*.jar
    local latest
    if latest="$(find_latest_glob "$pattern" 2>/dev/null)"; then
      printf '%s\n' "$latest"
      return 0
    fi
    log_error "uber-apk-signer JAR not found in $TOOLS_DIR. Place uber-apk-signer.jar or uber-apk-signer-*.jar there."
    exit 1
  }

  find_jadx_cli() {
    local preferred="$TOOLS_DIR/jadx/bin/jadx"
    if [[ -x "$preferred" ]]; then
      printf '%s\n' "$preferred"
      return 0
    fi
    local pattern="$TOOLS_DIR"/jadx*/bin/jadx
    local latest
    if latest="$(find_latest_glob "$pattern" 2>/dev/null)"; then
      if [[ -x "$latest" ]]; then
        printf '%s\n' "$latest"
        return 0
      fi
    fi
    log_error "jadx executable not found. Place unpacked JADX under $TOOLS_DIR (e.g., tools/jadx-*/bin/jadx)."
    exit 1
  }

  maybe_open_with_code() {
    local path="$1"
    if command -v code >/dev/null 2>&1; then
      code "$path" >/dev/null 2>&1 &
      return
    fi
    /usr/bin/open -a "Visual Studio Code" "$path" >/dev/null 2>&1 || true
  }

  confirm() {
    local prompt="${1:-Proceed? (y/N): }"
    local reply
    read -r -p "$prompt" reply
    local lowered
    lowered="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
    [[ "$lowered" == "y" || "$lowered" == "yes" ]]
  }

  timestamp() {
    date +"%Y%m%d-%H%M%S"
  }
fi
