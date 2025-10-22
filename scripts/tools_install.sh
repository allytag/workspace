#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

FALLBACK_APKTOOL_VERSION="2.9.3"
FALLBACK_UBER_APK_SIGNER_VERSION="1.3.0"
FALLBACK_JADX_VERSION="1.5.0"
DEFAULT_JDK_FEATURE_VERSION="21"

APKTOOL_VERSION="${APKTOOL_VERSION:-latest}"
UBER_APK_SIGNER_VERSION="${UBER_APK_SIGNER_VERSION:-latest}"
JADX_VERSION="${JADX_VERSION:-latest}"
JDK_FEATURE_VERSION="${JDK_FEATURE_VERSION:-$DEFAULT_JDK_FEATURE_VERSION}"
JDK_VERSION="${JDK_VERSION:-latest-lts}"

RESOLVED_APKTOOL_VERSION=""
RESOLVED_UBER_APK_SIGNER_VERSION=""
RESOLVED_JADX_VERSION=""
RESOLVED_JDK_VERSION=""

ALL_TOOLS=(apktool uber-apk-signer platform-tools jadx jdk)

usage() {
  cat <<'EOF'
Usage: tools_install.sh [options]

Install or update the bundled workspace tools under ./tools.

Options:
  --force           Re-download and reinstall even if a tool already exists.
  --only NAME       Install only the given tool (repeatable). Available names:
                    apktool, uber-apk-signer, platform-tools, jadx, jdk
  --list            Print the supported tool names and exit.
  -h, --help        Show this help message and exit.

Notes:
  - The JDK installer refreshes work/env.sh so JAVA_HOME points at the bundled JDK.
  - All downloads stay under the workspace (tools/ and work/).

Environment overrides:
  APKTOOL_VERSION, UBER_APK_SIGNER_VERSION, JADX_VERSION,
  JDK_VERSION, JDK_FEATURE_VERSION
EOF
}

FORCE=false
REQUESTED=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    --only)
      shift
      if [[ $# -eq 0 ]]; then
        log_error "--only requires a tool name."
        usage
        exit 1
      fi
      REQUESTED+=("$1")
      shift
      ;;
    --list)
      printf '%s\n' "${ALL_TOOLS[@]}"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

request_includes() {
  local needle="$1"
  if [[ ${#REQUESTED[@]} -eq 0 ]]; then
    return 0
  fi
  local item
  for item in "${REQUESTED[@]}"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

validate_requested() {
  if [[ ${#REQUESTED[@]} -eq 0 ]]; then
    return
  fi
  local item matched candidate
  for item in "${REQUESTED[@]}"; do
    matched=false
    for candidate in "${ALL_TOOLS[@]}"; do
      if [[ "$candidate" == "$item" ]]; then
        matched=true
        break
      fi
    done
    if [[ "$matched" == false ]]; then
      log_error "Unknown tool: $item"
      usage
      exit 1
    fi
  done
}

validate_requested

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Missing required command: $cmd"
    exit 1
  fi
}

needs_python=false
for tool in "${ALL_TOOLS[@]}"; do
  if ! request_includes "$tool"; then
    continue
  fi
  case "$tool" in
    apktool)
      case "$APKTOOL_VERSION" in
        latest|LATEST|Latest) needs_python=true ;;
      esac
      ;;
    uber-apk-signer)
      case "$UBER_APK_SIGNER_VERSION" in
        latest|LATEST|Latest) needs_python=true ;;
      esac
      ;;
    jadx)
      case "$JADX_VERSION" in
        latest|LATEST|Latest) needs_python=true ;;
      esac
      ;;
    jdk)
      case "$JDK_VERSION" in
        latest|LATEST|Latest|latest-lts|LATEST-LTS|Latest-LTS) needs_python=true ;;
      esac
      ;;
  esac
done

if $needs_python; then
  require_cmd python3
fi

require_cmd curl

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/workspace-tools.XXXXXX")"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

download() {
  local url="$1"
  local dest="$2"
  local tmp="$dest.part"
  curl --fail --location --progress-bar "$url" --output "$tmp"
  mv "$tmp" "$dest"
}

github_api_fetch_latest_release() {
  local repo="$1"
  local dest="$2"
  local url="https://api.github.com/repos/${repo}/releases/latest"
  local curl_args=(--fail --silent --show-error --location -H "Accept: application/vnd.github+json")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28")
  fi
  curl "${curl_args[@]}" "$url" --output "$dest"
}

resolve_github_latest_version() {
  local repo="$1"
  local strip_prefix="${2:-}"
  local tmp
  tmp="$(mktemp "$TMP_ROOT/github.${repo//\//_}.XXXXXX.json")"
  if ! github_api_fetch_latest_release "$repo" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  local version
  if ! version="$(python3 - "$tmp" "$strip_prefix" <<'PY'
import json
import sys

path = sys.argv[1]
prefix = sys.argv[2]

with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

tag = data.get("tag_name")
if not tag:
    raise SystemExit(1)

if prefix:
    if tag.lower().startswith(prefix.lower()):
        tag = tag[len(prefix):]

print(tag.strip())
PY
)"; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  printf '%s\n' "$version"
}

get_apktool_version() {
  if [[ -n "$RESOLVED_APKTOOL_VERSION" ]]; then
    printf '%s\n' "$RESOLVED_APKTOOL_VERSION"
    return 0
  fi
  case "$APKTOOL_VERSION" in
    latest|LATEST|Latest)
      if resolved="$(resolve_github_latest_version "iBotPeaches/Apktool" "v")"; then
        RESOLVED_APKTOOL_VERSION="$resolved"
        log_info "Resolved latest apktool version: $RESOLVED_APKTOOL_VERSION" >&2
      else
        RESOLVED_APKTOOL_VERSION="$FALLBACK_APKTOOL_VERSION"
        log_warn "Unable to resolve latest apktool version; falling back to ${RESOLVED_APKTOOL_VERSION}." >&2
      fi
      ;;
    *)
      RESOLVED_APKTOOL_VERSION="$APKTOOL_VERSION"
      ;;
  esac
  printf '%s\n' "$RESOLVED_APKTOOL_VERSION"
}

get_uber_apk_signer_version() {
  if [[ -n "$RESOLVED_UBER_APK_SIGNER_VERSION" ]]; then
    printf '%s\n' "$RESOLVED_UBER_APK_SIGNER_VERSION"
    return 0
  fi
  case "$UBER_APK_SIGNER_VERSION" in
    latest|LATEST|Latest)
      if resolved="$(resolve_github_latest_version "patrickfav/uber-apk-signer" "v")"; then
        RESOLVED_UBER_APK_SIGNER_VERSION="$resolved"
        log_info "Resolved latest uber-apk-signer version: $RESOLVED_UBER_APK_SIGNER_VERSION" >&2
      else
        RESOLVED_UBER_APK_SIGNER_VERSION="$FALLBACK_UBER_APK_SIGNER_VERSION"
        log_warn "Unable to resolve latest uber-apk-signer version; falling back to ${RESOLVED_UBER_APK_SIGNER_VERSION}." >&2
      fi
      ;;
    *)
      RESOLVED_UBER_APK_SIGNER_VERSION="$UBER_APK_SIGNER_VERSION"
      ;;
  esac
  printf '%s\n' "$RESOLVED_UBER_APK_SIGNER_VERSION"
}

get_jadx_version() {
  if [[ -n "$RESOLVED_JADX_VERSION" ]]; then
    printf '%s\n' "$RESOLVED_JADX_VERSION"
    return 0
  fi
  case "$JADX_VERSION" in
    latest|LATEST|Latest)
      if resolved="$(resolve_github_latest_version "skylot/jadx" "v")"; then
        RESOLVED_JADX_VERSION="$resolved"
        log_info "Resolved latest jadx version: $RESOLVED_JADX_VERSION" >&2
      else
        RESOLVED_JADX_VERSION="$FALLBACK_JADX_VERSION"
        log_warn "Unable to resolve latest jadx version; falling back to ${RESOLVED_JADX_VERSION}." >&2
      fi
      ;;
    *)
      RESOLVED_JADX_VERSION="$JADX_VERSION"
      ;;
  esac
  printf '%s\n' "$RESOLVED_JADX_VERSION"
}

get_jdk_version() {
  if [[ -n "$RESOLVED_JDK_VERSION" ]]; then
    printf '%s\n' "$RESOLVED_JDK_VERSION"
    return 0
  fi
  case "$JDK_VERSION" in
    latest|LATEST|Latest|latest-lts|LATEST-LTS|Latest-LTS)
      local feature="$JDK_FEATURE_VERSION"
      if [[ -z "$feature" ]]; then
        log_error "JDK_FEATURE_VERSION must be set when requesting the latest JDK." >&2
        return 1
      fi
      if ! [[ "$feature" =~ ^[0-9]+$ ]]; then
        log_error "JDK_FEATURE_VERSION must be a numeric value (got: $feature)." >&2
        return 1
      fi
      if resolved="$(resolve_github_latest_version "adoptium/temurin${feature}-binaries" "jdk-")"; then
        RESOLVED_JDK_VERSION="$resolved"
        log_info "Resolved latest Temurin JDK ${feature} version: $RESOLVED_JDK_VERSION" >&2
      else
        log_error "Unable to resolve latest Temurin JDK release for feature ${feature}. Set JDK_VERSION manually." >&2
        return 1
      fi
      ;;
    *)
      RESOLVED_JDK_VERSION="$JDK_VERSION"
      ;;
  esac
  printf '%s\n' "$RESOLVED_JDK_VERSION"
}

update_env_java_home() {
  local rel_home="$1"
  ensure_dir "$WORK_DIR"
  local env_file="$WORK_DIR/env.sh"
  local filtered="$TMP_ROOT/env.sh.filtered"
  if [[ -f "$env_file" ]]; then
    awk '
      /^export[[:space:]]+JAVA_HOME=/ { next }
      /^export[[:space:]]+PATH=.*\$JAVA_HOME\/bin/ { next }
      { print }
    ' "$env_file" > "$filtered"
  else
    : > "$filtered"
  fi
  local output="${filtered}.new"
  {
    printf 'export JAVA_HOME="%s"\n' "$rel_home"
    printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
    cat "$filtered"
  } > "$output"
  mv "$output" "$env_file"
  rm -f "$filtered"
  log_info "Updated $env_file with JAVA_HOME=$rel_home"
}

detect_os_token() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux) echo "linux" ;;
    *)
      log_error "Unsupported operating system: $(uname -s)"
      exit 1
      ;;
  esac
}

detect_arch_token() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    arm64|aarch64) echo "aarch64" ;;
    *)
      log_error "Unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac
}

install_apktool() {
  local version
  if ! version="$(get_apktool_version)"; then
    exit 1
  fi
  local dest="$TOOLS_DIR/apktool.jar"
  if [[ -f "$dest" && $FORCE == false ]]; then
    log_info "apktool already present at $dest (use --force to replace)."
    return
  fi
  ensure_dir "$TOOLS_DIR"
  local url="https://github.com/iBotPeaches/Apktool/releases/download/v${version}/apktool_${version}.jar"
  local tmp="$TMP_ROOT/apktool-${version}.jar"
  log_info "Downloading apktool ${version}..."
  download "$url" "$tmp"
  mv "$tmp" "$dest"
  log_success "apktool ${version} ready at $dest"
}

install_uber_apk_signer() {
  local version
  if ! version="$(get_uber_apk_signer_version)"; then
    exit 1
  fi
  local dest="$TOOLS_DIR/uber-apk-signer.jar"
  if [[ -f "$dest" && $FORCE == false ]]; then
    log_info "uber-apk-signer already present at $dest (use --force to replace)."
    return
  fi
  ensure_dir "$TOOLS_DIR"
  local url="https://github.com/patrickfav/uber-apk-signer/releases/download/v${version}/uber-apk-signer-${version}.jar"
  local tmp="$TMP_ROOT/uber-apk-signer-${version}.jar"
  log_info "Downloading uber-apk-signer ${version}..."
  download "$url" "$tmp"
  mv "$tmp" "$dest"
  log_success "uber-apk-signer ${version} ready at $dest"
}

install_jadx() {
  require_cmd unzip
  local version
  if ! version="$(get_jadx_version)"; then
    exit 1
  fi
  local dest="$TOOLS_DIR/jadx"
  if [[ -d "$dest" && $FORCE == false ]]; then
    log_info "jadx already present at $dest (use --force to replace)."
    return
  fi
  local url="https://github.com/skylot/jadx/releases/download/v${version}/jadx-${version}.zip"
  local tmp="$TMP_ROOT/jadx-${version}.zip"
  log_info "Downloading jadx ${version}..."
  download "$url" "$tmp"
  log_info "Extracting jadx ${version}..."
  ensure_dir "$TOOLS_DIR"
  rm -rf "$dest"
  local extract_dir="$TMP_ROOT/jadx-extract"
  rm -rf "$extract_dir"
  mkdir -p "$extract_dir"
  unzip -q "$tmp" -d "$extract_dir"
  local candidate_dir="$extract_dir/jadx-${version}"
  if [[ -d "$candidate_dir" ]]; then
    mv "$candidate_dir" "$dest"
  else
    ensure_dir "$dest"
    shopt -s dotglob nullglob
    local entries=("$extract_dir"/*)
    if [[ ${#entries[@]} -eq 0 ]]; then
      shopt -u dotglob nullglob
      log_error "Failed to extract jadx ${version}; archive was empty."
      exit 1
    fi
    mv "${entries[@]}" "$dest"/
    shopt -u dotglob nullglob
  fi
  rm -rf "$extract_dir"
  chmod +x "$dest"/bin/jadx "$dest"/bin/jadx-gui
  log_success "jadx ${version} installed at $dest"
}

install_platform_tools() {
  require_cmd unzip
  local dest="$TOOLS_DIR/platform-tools"
  if [[ -d "$dest" && $FORCE == false ]]; then
    log_info "platform-tools already present at $dest (use --force to replace)."
    return
  fi
  local os_token
  case "$(uname -s)" in
    Darwin) os_token="darwin" ;;
    Linux) os_token="linux" ;;
    *)
      log_error "platform-tools installer only supports macOS and Linux."
      exit 1
      ;;
  esac
  local url="https://dl.google.com/android/repository/platform-tools-latest-${os_token}.zip"
  local tmp="$TMP_ROOT/platform-tools.zip"
  log_info "Downloading Android platform-tools (${os_token})..."
  download "$url" "$tmp"
  log_info "Extracting platform-tools..."
  rm -rf "$dest"
  unzip -q "$tmp" -d "$TMP_ROOT"
  mv "$TMP_ROOT/platform-tools" "$dest"
  log_success "platform-tools installed at $dest"
}

install_jdk() {
  require_cmd tar
  local version
  if ! version="$(get_jdk_version)"; then
    exit 1
  fi
  local dest="$TOOLS_DIR/jdk-${version}"
  if [[ -d "$dest" && $FORCE == false ]]; then
    log_info "JDK already present at $dest (use --force to replace)."
    return
  fi

  local version_base="${version%%+*}"
  local build="${version##*+}"
  local major="${version_base%%.*}"
  if [[ "$version" != *"+"* || -z "$version_base" || "$version" == "$build" ]]; then
    log_error "Unsupported Temurin JDK version format: ${version}"
    exit 1
  fi
  local os_token
  os_token="$(detect_os_token)"
  local arch_token
  arch_token="$(detect_arch_token)"

  local release_tag="jdk-${version}"
  local release_tag_url="${release_tag//+/%2B}"
  local archive="OpenJDK${major}U-jdk_${arch_token}_${os_token}_hotspot_${version_base}_${build}.tar.gz"
  local url="https://github.com/adoptium/temurin${major}-binaries/releases/download/${release_tag_url}/${archive}"
  local tmp="$TMP_ROOT/${archive}"

  log_info "Downloading Temurin JDK ${version} (${arch_token}/${os_token})..."
  download "$url" "$tmp"
  log_info "Extracting JDK ${version}..."
  rm -rf "$dest"
  tar -xzf "$tmp" -C "$TMP_ROOT"
  if [[ ! -d "$TMP_ROOT/jdk-${version}" ]]; then
    log_error "Expected directory jdk-${version} after extracting; archive layout may have changed."
    exit 1
  fi
  mv "$TMP_ROOT/jdk-${version}" "$dest"
  local rel_dir
  if [[ "$dest" == "$BASE_DIR/"* ]]; then
    rel_dir="${dest#$BASE_DIR/}"
  else
    rel_dir="$dest"
  fi
  local rel_home="$rel_dir"
  if [[ -d "$dest/Contents/Home" ]]; then
    rel_home="$rel_dir/Contents/Home"
  elif [[ -d "$dest/Home" ]]; then
    rel_home="$rel_dir/Home"
  fi
  update_env_java_home "$rel_home"
  log_success "Temurin JDK ${version} installed at $dest"
}

process_tool() {
  local tool="$1"
  if ! request_includes "$tool"; then
    return
  fi
  local func="install_${tool//-/_}"
  if ! declare -F "$func" >/dev/null 2>&1; then
    log_error "Installer function missing for $tool"
    exit 1
  fi
  "$func"
}

ensure_dir "$TOOLS_DIR"

for tool in "${ALL_TOOLS[@]}"; do
  process_tool "$tool"
done

log_success "All requested tools processed."
