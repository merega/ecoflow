#!/usr/bin/env python3
import os, time, random, hmac, hashlib, requests, sys

def load_env(path):
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                k, v = line.split("=", 1)
                os.environ.setdefault(k, v)
    except FileNotFoundError:
        pass

load_env("/srv/ecoflow/.env")

BASE = os.getenv("ECOFLOW_BASE", "https://api-e.ecoflow.com").rstrip("/")
ACCESS_KEY = os.environ["ECOFLOW_ACCESS_KEY"]
SECRET_KEY = os.environ["ECOFLOW_SECRET_KEY"]
SN = os.environ["ECOFLOW_SN"]

PATH = "/iot-open/sign/device/quota/all"
URL = BASE + PATH

timestamp = str(int(time.time() * 1000))
nonce = str(random.randint(100000, 999999))

sign_str = f"sn={SN}&accessKey={ACCESS_KEY}&nonce={nonce}&timestamp={timestamp}"
sign = hmac.new(SECRET_KEY.encode(), sign_str.encode(), hashlib.sha256).hexdigest()

headers = {
    "accessKey": ACCESS_KEY,
    "nonce": nonce,
    "timestamp": timestamp,
    "sign": sign,
}

r = requests.get(URL, headers=headers, params={"sn": SN}, timeout=20)
j = r.json()

if str(j.get("code")) != "0":
    print("ERROR:", j)
    sys.exit(2)

data = j.get("data", {})
inv_in = int(data.get("inv.inputWatts", 0) or 0)
out_sum = int(data.get("pd.wattsOutSum", 0) or 0)
soc = data.get("pd.soc")

if inv_in > 0:
    print(f"AC=1 inv.inputWatts={inv_in}W out={out_sum}W soc={soc}")
    sys.exit(0)
else:
    print(f"AC=0 inv.inputWatts={inv_in}W out={out_sum}W soc={soc}")
    sys.exit(1)
