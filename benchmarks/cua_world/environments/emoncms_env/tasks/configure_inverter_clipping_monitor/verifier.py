#!/usr/bin/env python3
"""
Verifier for configure_inverter_clipping_monitor task.

Verifies:
1. Feeds exist: solar_raw_W, solar_excess_W, solar_lost_kwh
2. Input 'solar_pv' has a process list
3. Process list follows the logic:
   - Log to Feed (raw)
   - + Offset (-3600)
   - Allow Positive
   - Log to Feed (excess)
   - Power to kWh (lost)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Emoncms Process ID Mapping (Standard IDs)
# Derived from Emoncms default installations
PROCESS_IDS = {
    "1": "log_to_feed",
    "2": "power_to_kwh",
    "4": "power_to_kwhd",
    "5": "accumulator",
    "6": "scale",      # x
    "7": "offset",     # +
    "8": "allow_positive",
    "9": "allow_negative",
    "22": "calibration" # Sometimes used for scale/offset
}

def verify_clipping_monitor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Parse Feeds
    feeds = result.get("feeds", [])
    feed_map = {str(f["id"]): f for f in feeds} # ID -> Feed Dict
    feed_name_map = {f["name"]: f for f in feeds} # Name -> Feed Dict

    # Parse Process List
    # format: "1:12,7:-3600,8:0" -> list of (id, value)
    raw_plist = result.get("input", {}).get("process_list_str", "")
    if not raw_plist:
        return {"passed": False, "score": 0, "feedback": "No input processes configured."}

    process_chain = []
    for p in raw_plist.split(","):
        if ":" in p:
            pid, val = p.split(":", 1)
            pname = PROCESS_IDS.get(str(pid), f"unknown_{pid}")
            process_chain.append({"id": str(pid), "name": pname, "value": val})

    score = 0
    feedback = []
    
    # 1. Verify Feeds Existence (30 pts)
    required_feeds = ["solar_raw_W", "solar_excess_W", "solar_lost_kwh"]
    feeds_found = 0
    for fname in required_feeds:
        if fname in feed_name_map:
            f = feed_name_map[fname]
            # Check Engine (5 = PHPFina)
            if str(f.get("engine")) == "5":
                feeds_found += 1
                feedback.append(f"Feed '{fname}' found (PHPFina).")
            else:
                feedback.append(f"Feed '{fname}' found but wrong engine (expected PHPFina).")
                feeds_found += 0.5
        else:
            feedback.append(f"Feed '{fname}' NOT found.")
    
    score += (feeds_found / 3) * 30

    # 2. Verify Process Chain Logic (70 pts)
    # Expected Chain:
    # 1. Log to Feed -> solar_raw_W
    # 2. Offset -> -3600 (approx)
    # 3. Allow Positive
    # 4. Log to Feed -> solar_excess_W
    # 5. Power to kWh -> solar_lost_kwh

    if len(process_chain) < 5:
        feedback.append(f"Process chain too short (found {len(process_chain)}, expected >= 5).")
        return {"passed": False, "score": int(score), "feedback": " ".join(feedback)}

    # Step 1: Log Raw
    step1 = process_chain[0]
    if step1["name"] == "log_to_feed":
        fid = step1["value"]
        if fid in feed_map and feed_map[fid]["name"] == "solar_raw_W":
            score += 15
            feedback.append("Step 1 (Log Raw) correct.")
        else:
            feedback.append(f"Step 1 logs to wrong feed ID {fid}.")
    else:
        feedback.append(f"Step 1 is {step1['name']}, expected log_to_feed.")

    # Step 2: Offset -3600
    step2 = process_chain[1]
    # Allow for 'offset' (7) or 'calibration' (22)
    val = float(step2["value"])
    if step2["name"] in ["offset", "calibration"]:
        if -3601 <= val <= -3599:
            score += 20
            feedback.append("Step 2 (Offset -3600) correct.")
        else:
            feedback.append(f"Step 2 offset value {val} incorrect (expected -3600).")
    else:
        feedback.append(f"Step 2 is {step2['name']}, expected offset/calibration.")

    # Step 3: Allow Positive
    step3 = process_chain[2]
    if step3["name"] == "allow_positive":
        score += 15
        feedback.append("Step 3 (Allow Positive) correct.")
    else:
        feedback.append(f"Step 3 is {step3['name']}, expected allow_positive.")

    # Step 4: Log Excess
    step4 = process_chain[3]
    if step4["name"] == "log_to_feed":
        fid = step4["value"]
        if fid in feed_map and feed_map[fid]["name"] == "solar_excess_W":
            score += 10
            feedback.append("Step 4 (Log Excess) correct.")
        else:
            feedback.append(f"Step 4 logs to wrong feed ID {fid}.")
    else:
        feedback.append(f"Step 4 is {step4['name']}, expected log_to_feed.")

    # Step 5: Power to kWh
    step5 = process_chain[4]
    if step5["name"] == "power_to_kwh":
        fid = step5["value"]
        if fid in feed_map and feed_map[fid]["name"] == "solar_lost_kwh":
            score += 10
            feedback.append("Step 5 (Power to kWh) correct.")
        else:
            feedback.append(f"Step 5 target feed ID {fid} incorrect.")
    else:
        feedback.append(f"Step 5 is {step5['name']}, expected power_to_kwh.")

    passed = score >= 75
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }