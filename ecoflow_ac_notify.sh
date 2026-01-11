#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/srv/ecoflow/.env"
STATE_FILE="/srv/ecoflow/ac_state.txt"
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

: "${TG_BOT_TOKEN:?TG_BOT_TOKEN missing in .env}"
: "${TG_CHAT_ID:?TG_CHAT_ID missing in .env}"

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
  exit 0
fi

# Read previous state
if [[ -f "$STATE_FILE" ]]; then
  PREV=$(cat "$STATE_FILE" || true)
else
  PREV="unknown"
fi

# Notify only on change (or first run)
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

  echo "TG_RESP=$RESP"

  echo "$CURRENT" > "$STATE_FILE"
fi
