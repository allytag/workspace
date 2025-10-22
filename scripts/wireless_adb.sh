#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: wireless_adb.sh [options]

Options:
  --pair HOST:PORT     Pairing address (if omitted, prompt)
  --code CODE          Pairing code (if omitted, prompt)
  --connect HOST:PORT  Connect address (if omitted, prompt)
  --install            Install the most recent signed APK after connecting
  --add                Prompt for pairing/connecting (interactive add)
  --device SERIAL      Use this device serial for installation (skip prompt)
  --list-only          Only list connected devices
  -h, --help           Show this help
EOF
}

PAIR_ADDR=""
PAIR_CODE=""
CONNECT_ADDR=""
INSTALL_APK=false
TARGET_DEVICE=""
LIST_ONLY=false
ADD_DEVICE=false
declare -a ONLINE_DEVICES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pair)
      [[ $# -ge 2 ]] || { log_error "--pair requires HOST:PORT"; usage; }
      PAIR_ADDR="$2"
      shift 2
      ;;
    --code)
      [[ $# -ge 2 ]] || { log_error "--code requires pairing code"; usage; }
      PAIR_CODE="$2"
      shift 2
      ;;
    --connect)
      [[ $# -ge 2 ]] || { log_error "--connect requires HOST:PORT"; usage; }
      CONNECT_ADDR="$2"
      shift 2
      ;;
    --install)
      INSTALL_APK=true
      shift
      ;;
    --add)
      ADD_DEVICE=true
      shift
      ;;
    --device)
      [[ $# -ge 2 ]] || { log_error "--device requires a serial"; usage; }
      TARGET_DEVICE="$2"
      shift 2
      ;;
    --list-only)
      LIST_ONLY=true
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

ADB_BIN="$(detect_adb)"
log_info "Using adb at $ADB_BIN"

if $LIST_ONLY; then
  "$ADB_BIN" devices
  exit 0
fi

if [[ -n "$PAIR_ADDR" || $ADD_DEVICE == true ]]; then
  if [[ -z "$PAIR_ADDR" ]]; then
    if $ADD_DEVICE; then
      read -r -p "PAIR address (e.g., 192.168.1.50:37099): " PAIR_ADDR
    else
      log_error "--pair requires HOST:PORT"
      exit 1
    fi
  fi
  if [[ -z "$PAIR_CODE" ]]; then
    if $ADD_DEVICE; then
      read -r -p "PAIRING CODE (6 digits): " PAIR_CODE
    else
      log_error "--code required when using --pair non-interactively"
      exit 1
    fi
  fi
  if [[ -n "$PAIR_ADDR" && -n "$PAIR_CODE" ]]; then
    log_info "Pairing with $PAIR_ADDR"
    printf '%s' "$PAIR_CODE" | "$ADB_BIN" pair "$PAIR_ADDR"
  else
    log_warn "Skipping pairing (missing address or code)."
  fi
fi

if [[ -n "$CONNECT_ADDR" || $ADD_DEVICE == true ]]; then
  if [[ -z "$CONNECT_ADDR" ]]; then
    if $ADD_DEVICE; then
      read -r -p "CONNECT address (e.g., 192.168.1.50:5555): " CONNECT_ADDR
    else
      log_error "--connect requires HOST:PORT"
      exit 1
    fi
  fi
  if [[ -n "$CONNECT_ADDR" ]]; then
    log_info "Connecting to $CONNECT_ADDR"
    "$ADB_BIN" connect "$CONNECT_ADDR"
  fi
fi

log_info "Connected devices:"
devices_output="$("$ADB_BIN" devices)"
printf '%s\n' "$devices_output"
ONLINE_DEVICES=()
while IFS= read -r serial; do
  [[ -n "$serial" ]] && ONLINE_DEVICES+=("$serial")
done < <(printf '%s\n' "$devices_output" | awk '$2 == "device" {print $1}')

set +e
LATEST_SIGNED="$(ls -t "$WORK_DIR"/out/*signed.apk 2>/dev/null | head -n1)"
set -e

if $INSTALL_APK; then
  if [[ -z "$LATEST_SIGNED" ]]; then
    log_warn "No signed APK found in $WORK_DIR/out."
    exit 1
  fi

  selected_device="$TARGET_DEVICE"
  if [[ -z "$selected_device" ]]; then
    if [[ ${#ONLINE_DEVICES[@]} -eq 0 ]]; then
      log_warn "No online devices detected. Connect a device and try again."
      exit 1
    elif [[ ${#ONLINE_DEVICES[@]} -eq 1 ]]; then
      selected_device="${ONLINE_DEVICES[0]}"
    else
      log_info "Multiple devices detected:"
      for idx in "${!ONLINE_DEVICES[@]}"; do
        printf '  [%d] %s\n' $((idx + 1)) "${ONLINE_DEVICES[idx]}"
      done
      read -r -p "Select device [1]: " selection
      if [[ -z "$selection" ]]; then
        selection=1
      fi
      if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        log_error "Invalid selection: $selection"
        exit 1
      fi
      index=$((selection - 1))
      if (( index < 0 || index >= ${#ONLINE_DEVICES[@]} )); then
        log_error "Selection out of range."
        exit 1
      fi
      selected_device="${ONLINE_DEVICES[index]}"
    fi
  else
    if [[ ${#ONLINE_DEVICES[@]} -gt 0 ]]; then
      found=0
      for device in "${ONLINE_DEVICES[@]}"; do
        if [[ "$device" == "$selected_device" ]]; then
          found=1
          break
        fi
      done
      if (( !found )); then
        log_warn "Specified device $selected_device not currently listed; attempting install anyway."
      fi
    fi
  fi

  if [[ -z "$selected_device" ]]; then
    log_error "No device selected for installation."
    exit 1
  fi

  log_info "Installing $LATEST_SIGNED on $selected_device"
  "$ADB_BIN" -s "$selected_device" install -r "$LATEST_SIGNED"
  log_success "Install complete on $selected_device."
else
  if [[ -n "$LATEST_SIGNED" ]]; then
    if [[ ${#ONLINE_DEVICES[@]} -eq 1 ]]; then
      log_info "To install latest signed APK run:"
      echo "  \"$ADB_BIN\" -s \"${ONLINE_DEVICES[0]}\" install -r \"$LATEST_SIGNED\""
    elif [[ ${#ONLINE_DEVICES[@]} -gt 1 ]]; then
      log_info "Multiple devices detected. Install with:"
      echo "  \"$ADB_BIN\" -s \"<device-serial>\" install -r \"$LATEST_SIGNED\""
      log_info "Or rerun this script with --install --device <device-serial>."
    else
      log_info "To install once a device is connected:"
      echo "  \"$ADB_BIN\" install -r \"$LATEST_SIGNED\""
    fi
  else
    log_warn "No signed APK found in $WORK_DIR/out."
  fi
fi
