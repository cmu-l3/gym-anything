#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${WEIRD_CAPTCHA_STATE_DIR:-/tmp/weird_captcha_gym}"

python3 - <<'PY'
from __future__ import annotations

import json
import os
import time
from pathlib import Path

state_dir = Path(os.environ.get("WEIRD_CAPTCHA_STATE_DIR", "/tmp/weird_captcha_gym"))

def read_json(name: str) -> dict:
    path = state_dir / name
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return {"_error": str(exc)}
    return data if isinstance(data, dict) else {"_value": data}

payload = {
    "exported_at": time.time(),
    "public_state": read_json("public_state.json"),
    "ground_truth": read_json("ground_truth.json"),
    "result": read_json("result.json"),
}
target = Path("/tmp/task_result.json")
tmp = target.with_suffix(".json.tmp")
tmp.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
os.replace(tmp, target)
target.chmod(0o666)
print(json.dumps({"ok": True, "target": str(target)}))
PY
