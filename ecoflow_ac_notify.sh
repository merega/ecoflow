#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/srv/ecoflow/.env"
STATE_FILE="/srv/ecoflow/ac_state.txt"
BATT_STATE_FILE="/srv/ecoflow/batt_low_state.txt"
TMP_OUT="/tmp/ecoflow_last.txt"

PY="/usr/bin/python3"
SCRIPT="/srv/ecoflow/ecoflow_ac_only.py"

# Load .env (export variables)
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE"
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Required vars
: "${TG_BOT_TOKEN:?TG_BOT_TOKEN missing in .env}"
: "${TG_CHAT_ID:?TG_CHAT_ID missing in .env}"

# Optional vars with defaults
BATT_LOW_THRESHOLD="${BATT_LOW_THRESHOLD:-10}"
BATT_RECOVER_THRESHOLD="${BATT_RECOVER_THRESHOLD:-12}"

# --- run check (IMPORTANT: don't let 'set -e' kill us on RC=1) ---
set +e
"$PY" "$SCRIPT" >"$TMP_OUT" 2>&1
RC=$?
set -e

# RC mapping:
# 0 => AC present
# 1 => AC absent
# 2 => script/API error (ignore, do not change state)
if [[ "$RC" == "0" ]]; then
  CURRENT=1
elif [[ "$RC" == "1" ]]; then
  CURRENT=0
else
  # Optional: log errors
  # echo "$(date -Is) ERROR RC=$RC $(cat "$TMP_OUT")" >> /srv/ecoflow/ecoflow_errors.log
  exit 0
fi

# Read previous AC state
if [[ -f "$STATE_FILE" ]]; then
  PREV=$(cat "$STATE_FILE" || true)
else
  PREV="unknown"
fi

# Extract SOC from python output line like: "... soc=83"
SOC="$(grep -oE 'soc=[0-9]+' "$TMP_OUT" | head -n1 | cut -d= -f2 || true)"
SOC="${SOC:-}"
if [[ -n "$SOC" ]]; then
  SOC="${SOC// /}"
fi

# --- Notify AC change (only on change or first run) ---
if [[ "$PREV" != "$CURRENT" ]]; then
  MSG=$(cat "$TMP_OUT" || true)

  if [[ "$CURRENT" == "1" ]]; then
    TEXT="🔌 *Сеть ВКЛ*\n$MSG"
  else
    TEXT="⚠️ *Сеть ВЫКЛ*\n$MSG"
  fi

  RESP=$(curl -sS -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    --data-urlencode text="$TEXT" \
    -d parse_mode="Markdown")

  # Uncomment for debug:
  # echo "TG_RESP_AC=$RESP" >&2

  echo "$CURRENT" > "$STATE_FILE"
fi

# --- Low battery notify (once, with hysteresis) ---
# Read previous low-batt flag
if [[ -f "$BATT_STATE_FILE" ]]; then
  BATT_PREV="$(cat "$BATT_STATE_FILE" || true)"
else
  BATT_PREV="0"
fi

# SOC must be a number
if [[ "$SOC" =~ ^[0-9]+$ ]]; then
  # Trigger once when SOC <= threshold AND not already notified
  # (Optionally, you can require CURRENT==0 to notify only when no AC)
  if (( SOC <= BATT_LOW_THRESHOLD )) && [[ "$BATT_PREV" != "1" ]]; then
    TEXT="🪫 *Низкий заряд EcoFlow*: *${SOC}%* (≤ ${BATT_LOW_THRESHOLD}%)"
    RESP=$(curl -sS -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
      -d chat_id="${TG_CHAT_ID}" \
      --data-urlencode text="$TEXT" \
      -d parse_mode="Markdown")

    # Uncomment for debug:
    # echo "TG_RESP_BATT=$RESP" >&2

    echo "1" > "$BATT_STATE_FILE"
  fi

  # Reset flag only after recovery above recover threshold
  if (( SOC >= BATT_RECOVER_THRESHOLD )) && [[ "$BATT_PREV" == "1" ]]; then
    echo "0" > "$BATT_STATE_FILE"
  fi
fi
