#!/usr/bin/env python3
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ENV_FILE = Path("/srv/ecoflow/.env")
STATE_FILE = Path("/srv/ecoflow/ac_state.txt")
BATT_STATE_FILE = Path("/srv/ecoflow/batt_low_state.txt")

PYTHON = "/usr/bin/python3"
AC_SCRIPT = Path("/srv/ecoflow/ecoflow_ac_only.py")

def load_env(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Missing env file: {path}")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        v = v.strip().strip('"').strip("'")
        # do not overwrite existing env
        os.environ.setdefault(k, v)

def read_state(path: Path, default: str = "unknown") -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return default
    except Exception:
        return default

def write_state(path: Path, value: str) -> None:
    path.write_text(str(value).strip() + "\n", encoding="utf-8")

def telegram_send(bot_token: str, chat_id: str, text: str, parse_mode: str = "Markdown") -> str:
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    data = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": parse_mode,
    }
    body = urllib.parse.urlencode(data).encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.read().decode("utf-8", errors="replace")

def run_ac_check() -> tuple[int, str, int | None]:
    """
    Returns:
      current_ac: 1 if AC present, 0 if absent
      output: stdout/stderr combined
      soc: parsed SOC or None
    Raises:
      RuntimeError on script/API errors (rc not 0/1)
    """
    proc = subprocess.run(
        [PYTHON, str(AC_SCRIPT)],
        capture_output=True,
        text=True,
    )
    out = (proc.stdout or "") + (proc.stderr or "")
    out = out.strip()

    # exit 0 => AC=1, exit 1 => AC=0, exit 2 => error
    if proc.returncode == 0:
        current = 1
    elif proc.returncode == 1:
        current = 0
    else:
        raise RuntimeError(f"AC script error rc={proc.returncode}: {out}")

    # parse soc=NN
    m = re.search(r"\bsoc=(\d+)\b", out)
    soc = int(m.group(1)) if m else None

    return current, out, soc

def main() -> int:
    load_env(ENV_FILE)

    tg_token = os.environ.get("TG_BOT_TOKEN", "").strip()
    tg_chat = os.environ.get("TG_CHAT_ID", "").strip()
    if not tg_token:
        print("ERROR: TG_BOT_TOKEN missing in .env", file=sys.stderr)
        return 2
    if not tg_chat:
        print("ERROR: TG_CHAT_ID missing in .env", file=sys.stderr)
        return 2

    batt_low = int(os.environ.get("BATT_LOW_THRESHOLD", "10"))
    batt_rec = int(os.environ.get("BATT_RECOVER_THRESHOLD", "12"))

    try:
        current, msg_line, soc = run_ac_check()
    except Exception as e:
        # Важно: при ошибках API/сети не шлём "ложные" уведомления
        print(f"INFO: skip notify due to error: {e}", file=sys.stderr)
        return 0

    prev = read_state(STATE_FILE, default="unknown")

    # 1) Notify on AC change
    if prev != str(current):
        if current == 1:
            text = "🔌 *Сеть ВКЛ*\n" + msg_line
        else:
            text = "⚠️ *Сеть ВЫКЛ*\n" + msg_line

        resp = telegram_send(tg_token, tg_chat, text, parse_mode="Markdown")
        # Для отладки можно раскомментировать:
        # print("TG_RESP_AC=", resp)
        write_state(STATE_FILE, str(current))

    # 2) Low battery notify (once with hysteresis)
    batt_prev = read_state(BATT_STATE_FILE, default="0").strip() or "0"

    if soc is not None:
        # notify once when SOC <= threshold and not already notified
        if soc <= batt_low and batt_prev != "1":
            text = f"🪫 *Низкий заряд EcoFlow*: *{soc}%* (≤ {batt_low}%)"
            resp = telegram_send(tg_token, tg_chat, text, parse_mode="Markdown")
            # print("TG_RESP_BATT=", resp)
            write_state(BATT_STATE_FILE, "1")

        # reset flag after recovery above recover threshold
        if soc >= batt_rec and batt_prev == "1":
            write_state(BATT_STATE_FILE, "0")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
