#!/usr/bin/env bash
set -euo pipefail

# === Settings (Global) ===
PAYLOAD_DUMPER="${PAYLOAD_DUMPER:-}"

# --- Utilities (Helper Functions) ---
log() { echo "[*] $*" >&2; }
warn() { echo "[!] $*" >&2; }
die() { echo "[x] $*" >&2; exit 1; }

function extract_and_clean() {
  local zip_in="$1"
  local img_out="$2"
  local base_work="$3"

  # Create a unique temp directory to prevent file collision (OOS vs COS)
  local temp_dir="$base_work/tmp_extract_$(date +%s%N)"
  mkdir -p "$temp_dir"

  log "Processing: $zip_in -> $img_out"

  # Extract payload.bin to temp dir
  unzip -o "$zip_in" payload.bin -d "$temp_dir" >/dev/null

  # Dump odm partition to temp dir
  payload-dumper-go -p odm -o "$temp_dir" "$temp_dir/payload.bin" >/dev/null

  # Find the extracted image within the isolated temp dir
  local extracted
  extracted=$(find "$temp_dir" -name "odm*.img" -maxdepth 1 | head -n 1)
  
  if [[ -f "$extracted" ]]; then
    # Rename and move to the base work directory
    mv "$extracted" "$base_work/$img_out"
    log "Created: $base_work/$img_out"
  else
    rm -rf "$temp_dir"
    die "Failed to extract odm.img from $zip_in"
  fi

  # Cleanup
  rm -rf "$temp_dir"
  rm -f "$zip_in"
}

function mount_odm() {
  local raw_img_in="$1"
  local mount_point="$2"
  
  local erofsfuse_bin="$(command -v erofsfuse)"

  log "Mounting $raw_img_in to $mount_point"
  mkdir -p "$mount_point"

  if ! "$erofsfuse_bin" "$raw_img_in" "$mount_point"; then
      warn "erofsfuse mount failed for $(basename "$raw_img_in")"
      umount "$mount_point" 2>/dev/null || true
      rmdir "$mount_point" 2>/dev/null || true
      return 1
  fi
  
  # Wait for mount to stabilize
  sleep 0.5
}

function unmount_odm() {
  local mount_point="$1"
  log "Unmounting $mount_point"
  umount "$mount_point" || warn "Failed to unmount $mount_point"
}
