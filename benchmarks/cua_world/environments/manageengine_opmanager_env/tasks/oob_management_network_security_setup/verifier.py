#!/usr/bin/env python3
"""Verifier for oob_management_network_security_setup task."""
import json
import os

# Scoring (100 pts total, pass threshold 60):
#  Criterion 1: Proxy IP (10.255.10.50) & Port (3128)          — 20 pts
#  Criterion 2: Proxy Auth User (svc_nms_proxy)                — 10 pts
#  Criterion 3: Proxy Exceptions (*.corp.local & 10.0.0.0/8)   — 15 pts
#  Criterion 4: Primary RADIUS (172.16.100.10 & MSCHAPv2)      — 20 pts
#  Criterion 5: Secondary RADIUS (172.16.100.11)               — 15 pts
#  Criterion 6: VLM Verification (Trajectories show config UI) — 20 pts

VLM_PROMPT = """You are assessing an agent's trajectory for configuring security settings in a web application.

Please look through these screenshots of the agent's screen over time.
Did the agent ever navigate to and interact with EITHER:
1. "Proxy Server Settings" (or similar proxy configuration form)
2. "RADIUS Authentication" (or similar authentication configuration form)

You should see form fields for things like Proxy IP, Port, Username OR Primary RADIUS server, Authentication Port, Protocol, etc.

Respond in JSON format:
{
    "proxy_or_radius_ui_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly describe if you see proxy or RADIUS settings forms being filled out."
}
"""


def verify_oob_management_network_security_setup(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', '/tmp/oob_security_result.json')
    local_path = '/tmp/oob_security_verify_result.json'

    try:
        env_info['copy_from_env'](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Check export_result.sh execution."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    proxy_db = data.get("proxy_db_raw", "").lower()
    radius_db = data.get("radius_db_raw", "").lower()

    score = 0
    details = []

    # ---------------------------------------------------------
    # Programmatic DB Checks
    # ---------------------------------------------------------

    # 1. Proxy IP & Port
    if "10.255.10.50" in proxy_db and "3128" in proxy_db:
        score += 20
        details.append("PASS: Proxy IP and Port found in database (+20)")
    else:
        details.append("FAIL: Proxy IP (10.255.10.50) or Port (3128) missing from proxy settings (0/20)")

    # 2. Proxy Auth
    if "svc_nms_proxy" in proxy_db:
        score += 10
        details.append("PASS: Proxy username 'svc_nms_proxy' found in database (+10)")
    else:
        details.append("FAIL: Proxy username missing (0/10)")

    # 3. Proxy Exceptions
    if "*.corp.local" in proxy_db and "10.0.0.0/8" in proxy_db:
        score += 15
        details.append("PASS: Proxy exception bypasses (*.corp.local, 10.0.0.0/8) found (+15)")
    else:
        details.append("FAIL: Proxy exceptions missing or incomplete (0/15)")

    # 4. Primary RADIUS & Protocol
    # Note: protocol MSCHAPv2 in db is often stored as 3 or the string itself. Check for string.
    if "172.16.100.10" in radius_db and "mschapv2" in radius_db:
        score += 20
        details.append("PASS: Primary RADIUS (172.16.100.10) and MSCHAPv2 protocol found (+20)")
    elif "172.16.100.10" in radius_db:
        score += 10
        details.append("PARTIAL: Primary RADIUS found, but MSCHAPv2 protocol missing or default used (+10)")
    else:
        details.append("FAIL: Primary RADIUS (172.16.100.10) not found (0/20)")

    # 5. Secondary RADIUS
    if "172.16.100.11" in radius_db:
        score += 15
        details.append("PASS: Secondary RADIUS (172.16.100.11) found (+15)")
    else:
        details.append("FAIL: Secondary RADIUS (172.16.100.11) not found (0/15)")

    # ---------------------------------------------------------
    # VLM Trajectory Check
    # ---------------------------------------------------------
    vlm_points_awarded = False
    if env_info.get("vlm_available", False) and "query_vlm" in env_info:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                query_vlm = env_info["query_vlm"]
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("proxy_or_radius_ui_visible"):
                        score += 20
                        vlm_points_awarded = True
                        details.append(f"PASS: VLM verified proxy/RADIUS configuration UI usage (+20). Reason: {parsed.get('reasoning','')}")
                    else:
                        details.append(f"FAIL: VLM did not observe proxy/RADIUS UI (0/20). Reason: {parsed.get('reasoning','')}")
                else:
                    details.append("FAIL: VLM parsing failed or empty result (0/20)")
            else:
                details.append("FAIL: No trajectory frames available for VLM (0/20)")
        except Exception as e:
            details.append(f"FAIL: VLM exception occurred ({e}) (0/20)")
    else:
        details.append("FAIL: VLM unavailable (0/20)")

    # Pass condition
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }