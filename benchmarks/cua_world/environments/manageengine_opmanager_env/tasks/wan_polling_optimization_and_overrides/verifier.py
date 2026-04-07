#!/usr/bin/env python3
"""
verifier.py — WAN Polling Optimization and Overrides

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Global Ping Timeout = 5000ms / 5s (20 pts)
  Criterion 2: Global Ping Retries = 4 (20 pts)
  Criterion 3: Global Polling Interval = 15m (20 pts)
  Criterion 4: Local-Core-SW-01 Polling Interval = 1m / 60s (20 pts)
  Criterion 5: Local-Core-SW-02 Polling Interval = 1m / 60s (20 pts)

Uses robust windowed regex search to verify values in the API response or DB dump.
"""

import json
import os
import re

RESULT_FILE = "/tmp/wan_polling_result.json"

def check_near(text, keyword, expected_values, window_size=80):
    """
    Find `keyword` in `text`, then search within +/- `window_size` characters
    to see if any of the `expected_values` (as standalone numbers) exist.
    """
    for match in re.finditer(keyword, text, re.IGNORECASE):
        start = max(0, match.start() - window_size)
        end = min(len(text), match.end() + window_size)
        window = text[start:end]
        for val in expected_values:
            # Match boundary to avoid matching '150' when looking for '15'
            if re.search(r'\b' + str(val) + r'\b', window):
                return True
    return False

def check_device_api(api_data, expected_values):
    """Check device API JSON specifically for poll/interval keys with expected values."""
    if not api_data:
        return False
    text = json.dumps(api_data).lower()
    return check_near(text, r'pollinterval|interval', expected_values, window_size=50)


def verify_wan_polling_optimization(traj, env_info, task_info):
    """Main verifier function."""
    result_file = task_info.get('metadata', {}).get('result_file', RESULT_FILE)
    local_path = '/tmp/wan_polling_verify_result.json'

    # Retrieve results via framework function
    try:
        env_info['copy_from_env'](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Ensure export_result.sh executed properly."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    sys_api = data.get("system_settings_api", {})
    dev1_api = data.get("device1_api", {})
    dev2_api = data.get("device2_api", {})
    db_raw = data.get("db_raw", "")

    # Combine all global text sources
    global_text = json.dumps(sys_api).lower() + "\n" + db_raw.lower()

    score = 0
    details = []

    # Criterion 1: Ping Timeout (5000 ms or 5 s) - 20 pts
    if check_near(global_text, r'timeout|ping_timeout', [5000, 5]):
        score += 20
        details.append("PASS: Global Ping Timeout set to 5000ms (+20)")
    else:
        details.append("FAIL: Global Ping Timeout (5000ms) not found (0/20)")

    # Criterion 2: Ping Retries (4) - 20 pts
    if check_near(global_text, r'retry|retries', [4]):
        score += 20
        details.append("PASS: Global Ping Retries set to 4 (+20)")
    else:
        details.append("FAIL: Global Ping Retries (4) not found (0/20)")

    # Criterion 3: Default Polling Interval (15 min) - 20 pts
    # Need to be careful not to match random IDs. Often called 'poll_interval' or 'availability_interval'
    if check_near(global_text, r'poll_interval|default_interval|availability', [15]):
        score += 20
        details.append("PASS: Global Default Polling Interval set to 15m (+20)")
    else:
        # Fallback to broader search
        if check_near(global_text, r'interval|poll', [15]):
            score += 20
            details.append("PASS: Global Default Polling Interval set to 15m (+20)")
        else:
            details.append("FAIL: Global Default Polling Interval (15m) not found (0/20)")

    # Criterion 4: Local-Core-SW-01 Polling Interval (1 min or 60 sec) - 20 pts
    sw1_found = False
    if check_device_api(dev1_api, [1, 60]):
        sw1_found = True
    elif check_near(db_raw, r'local-core-sw-01', [1, 60], window_size=250):
        sw1_found = True

    if sw1_found:
        score += 20
        details.append("PASS: Local-Core-SW-01 specific polling interval set to 1m (+20)")
    else:
        details.append("FAIL: Local-Core-SW-01 polling interval override (1m) not found (0/20)")

    # Criterion 5: Local-Core-SW-02 Polling Interval (1 min or 60 sec) - 20 pts
    sw2_found = False
    if check_device_api(dev2_api, [1, 60]):
        sw2_found = True
    elif check_near(db_raw, r'local-core-sw-02', [1, 60], window_size=250):
        sw2_found = True

    if sw2_found:
        score += 20
        details.append("PASS: Local-Core-SW-02 specific polling interval set to 1m (+20)")
    else:
        details.append("FAIL: Local-Core-SW-02 polling interval override (1m) not found (0/20)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(details)
    }