#!/usr/bin/env bash
# Entrypoint for the Tesla Dashcam Decryptor container.
# Translates environment variables (set in docker-compose.yml) into
# command-line arguments for tesla_dashcam_decrypt.py.
set -uo pipefail

APP_SCRIPT="${APP_SCRIPT:-/app/tesla_dashcam_decrypt.py}"
INPUT_DIR="${INPUT_DIR:-/input}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
BATCH_SIZE="${BATCH_SIZE:-20}"
DRY_RUN="${DRY_RUN:-false}"
REMUX="${REMUX:-false}"
RUN_MODE="${RUN_MODE:-once}"          # once | watch
SCAN_INTERVAL="${SCAN_INTERVAL:-3600}" # seconds between scans in watch mode
PUID="${PUID:-}"
PGID="${PGID:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
is_true() { case "${1,,}" in true|1|yes|on) return 0 ;; *) return 1 ;; esac; }

# ── Token: TESLA_TOKEN, or TESLA_TOKEN_FILE (e.g. a Docker secret) ──────────
TESLA_TOKEN="${TESLA_TOKEN:-}"
if [ -z "$TESLA_TOKEN" ] && [ -n "${TESLA_TOKEN_FILE:-}" ]; then
  if [ -r "$TESLA_TOKEN_FILE" ]; then
    TESLA_TOKEN="$(tr -d '\r\n' < "$TESLA_TOKEN_FILE")"
  else
    log "ERROR: TESLA_TOKEN_FILE is set but not readable: $TESLA_TOKEN_FILE"; exit 1
  fi
fi
# Tolerate people pasting "Bearer xxxxx" instead of just "xxxxx"
TESLA_TOKEN="${TESLA_TOKEN#Bearer }"
TESLA_TOKEN="${TESLA_TOKEN#bearer }"

if [ -z "$TESLA_TOKEN" ] || [ "$TESLA_TOKEN" = "PASTE_YOUR_BEARER_TOKEN_HERE" ]; then
  log "ERROR: TESLA_TOKEN is not set. Put your dashcam.tesla.com Bearer token in docker-compose.yml."
  exit 1
fi

# ── Validate settings ───────────────────────────────────────────────────────
if [ ! -d "$INPUT_DIR" ]; then
  log "ERROR: input folder $INPUT_DIR does not exist. Check the input volume in docker-compose.yml."
  exit 1
fi
if ! [[ "$BATCH_SIZE" =~ ^[0-9]+$ ]] || [ "$BATCH_SIZE" -lt 1 ]; then
  log "ERROR: BATCH_SIZE must be a positive integer (got '$BATCH_SIZE')"; exit 1
fi
if ! [[ "$SCAN_INTERVAL" =~ ^[0-9]+$ ]] || [ "$SCAN_INTERVAL" -lt 10 ]; then
  log "ERROR: SCAN_INTERVAL must be an integer >= 10 seconds (got '$SCAN_INTERVAL')"; exit 1
fi
if is_true "$REMUX" && ! command -v ffmpeg >/dev/null 2>&1; then
  log "ERROR: REMUX=true but ffmpeg is not installed (image was built with INSTALL_FFMPEG=false)"; exit 1
fi

case "${RUN_MODE,,}" in
  once|watch) ;;
  *) log "ERROR: RUN_MODE must be 'once' or 'watch' (got '$RUN_MODE')"; exit 1 ;;
esac

mkdir -p "$OUTPUT_DIR"

# ── Optional: run as a specific NAS user so output files are owned by you ───
RUN_AS=()
if [ "$(id -u)" = "0" ] && [ -n "$PUID" ] && [ -n "$PGID" ]; then
  chown "$PUID:$PGID" "$OUTPUT_DIR" 2>/dev/null || true
  RUN_AS=(setpriv --reuid="$PUID" --regid="$PGID" --clear-groups)
  log "Running as UID=$PUID GID=$PGID"
fi

# ── Build the command ───────────────────────────────────────────────────────
CMD=(python "$APP_SCRIPT" "$INPUT_DIR" "$OUTPUT_DIR" --token "$TESLA_TOKEN" --batch-size "$BATCH_SIZE")
is_true "$DRY_RUN" && CMD+=(--dry-run)
is_true "$REMUX"   && CMD+=(--remux)
if [ -n "$EXTRA_ARGS" ]; then
  # shellcheck disable=SC2206
  CMD+=($EXTRA_ARGS)
fi

log "Tesla Dashcam Decryptor"
log "  Input:       $INPUT_DIR"
log "  Output:      $OUTPUT_DIR"
log "  Batch size:  $BATCH_SIZE"
log "  Remux:       $REMUX"
log "  Dry run:     $DRY_RUN"
log "  Mode:        $RUN_MODE$( [ "$RUN_MODE" = "watch" ] && echo " (every ${SCAN_INTERVAL}s)")"
log "  Token:       ****${TESLA_TOKEN: -4}"

run_once() {
  "${RUN_AS[@]}" "${CMD[@]}"
  local rc=$?
  if [ $rc -eq 0 ]; then log "Run finished successfully."; else log "Run exited with code $rc."; fi
  return $rc
}

case "${RUN_MODE,,}" in
  once)
    run_once
    exit $?
    ;;
  watch)
    trap 'log "Stopping."; exit 0' TERM INT
    while true; do
      run_once
      log "Sleeping ${SCAN_INTERVAL}s until next scan..."
      sleep "$SCAN_INTERVAL" &
      wait $!
    done
    ;;
  *)
    log "ERROR: RUN_MODE must be 'once' or 'watch' (got '$RUN_MODE')"
    exit 1
    ;;
esac
