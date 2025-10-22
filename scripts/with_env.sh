#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: with_env.sh [options] [--] [command...]

Runs a command (or interactive shell) with the workspace environment applied.

Options:
  --shell [PATH]   Start an interactive shell (default: $SHELL or /bin/zsh).
  -h, --help       Show this help.

Examples:
  ./scripts/with_env.sh java -version
  ./scripts/with_env.sh --shell
EOF
}

START_SHELL=false
SHELL_PATH="${SHELL:-/bin/zsh}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)
      START_SHELL=true
      if [[ $# -ge 2 && "$2" != "--" ]]; then
        if [[ "$2" != -* ]]; then
          SHELL_PATH="$2"
          shift 2
          continue
        fi
      fi
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

if $START_SHELL; then
  log_info "Launching interactive shell with workspace environment."
  exec "$SHELL_PATH" -i
fi

if [[ $# -eq 0 ]]; then
  log_error "No command provided. Use --shell for interactive mode or supply a command."
  usage
  exit 1
fi

exec "$@"
