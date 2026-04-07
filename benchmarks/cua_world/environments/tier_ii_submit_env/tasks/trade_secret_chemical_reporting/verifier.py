#!/usr/bin/env python3
"""
Verifier for trade_secret_chemical_reporting task.

Scoring (100 pts total, pass threshold: 60):
  10 pts - Output file exists
  15 pts - Generic chemical name "Proprietary polyacrylamide coagulant blend" is present
  20 pts - Trade secret / withholding flag enabled for this chemical
  15 pts - Hazards (Skin corrosion, Serious eye damage) (7.5 pts each)
  15 pts - Quantities (Max 04, Avg 03, Days 365) (5 pts each)
  25 pts - Storage location (Tank, Ambient P, Ambient T, Liquid, "Chemical Feed Building 2") (5 pts each)
  
CRITICAL: The Trade Secret flag must be enabled for the task to be marked as passed.
"""
import json
import os
import tempfile
import re

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\trade_secret_result.json"

def verify_trade_secret_chemical_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 60)

    # Copy result JSON from container
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found or invalid: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Task not completed."}

    xml_content = result.get("xml_content", "")
    if not xml_content:
        return {"passed": False, "score": 0, "feedback": "Output .t2s file did not contain readable XML."}

    xml_lower = xml_content.lower()
    score = 10
    fb = ["PASS: Output file exists (+10)"]

    # Locate the chemical block (allow minor typos)
    if "polyacrylamide coagulant" in xml_lower or "proprietary polyacrylamide" in xml_lower:
        score += 15
        fb.append("PASS: Generic chemical name found (+15)")
        # Identify start index to isolate this chemical's XML block
        idx = max(xml_lower.find("polyacrylamide coagulant"), xml_lower.find("proprietary polyacrylamide"))
    else:
        fb.append("FAIL: Generic chemical name 'Proprietary polyacrylamide coagulant blend' not found")
        return {"passed": False, "score": score, "feedback": " | ".join(fb)}

    # Extract block surrounding the chemical to avoid cross-chemical pollution in checks
    start = max(0, idx - 2000)
    end = min(len(xml_lower), idx + 2500)
    block = xml_lower[start:end]

    # Check Trade Secret / Withholding flag
    has_ts = bool(re.search(r'<[^>]*(tradesecret|withheld|withholding)[^>]*>\s*(yes|y|true|1)\s*<', block)) or \
             bool(re.search(r'(tradesecret|withheld|withholding)=["\'](yes|y|true|1)["\']', block))
    
    if has_ts:
        score += 20
        fb.append("PASS: Trade Secret indicator enabled (+20)")
    else:
        fb.append("FAIL: Trade Secret indicator not enabled")

    # Check Hazards (Skin and Eye)
    if "skin" in block and ("corrosion" in block or "irritation" in block):
        score += 7.5
        fb.append("PASS: Skin hazard selected (+7.5)")
    else:
        fb.append("FAIL: Skin hazard not found")

    if "eye" in block and ("damage" in block or "irritation" in block):
        score += 7.5
        fb.append("PASS: Eye hazard selected (+7.5)")
    else:
        fb.append("FAIL: Eye hazard not found")

    # Check Quantities
    has_max = bool(re.search(r'<[^>]*max[^>]*amount[^>]*>\s*0?4\s*<', block)) or \
              bool(re.search(r'<[^>]*amount[^>]*>\s*0?4\s*<', block))
    has_avg = bool(re.search(r'<[^>]*(avg|average|ave)[^>]*amount[^>]*>\s*0?3\s*<', block)) or \
              bool(re.search(r'<[^>]*amount[^>]*>\s*0?3\s*<', block))
    has_days = "365" in block

    if has_max:
        score += 5
        fb.append("PASS: Max amount code 04 (+5)")
    else:
        fb.append("FAIL: Max amount code 04 not found")

    if has_avg:
        score += 5
        fb.append("PASS: Avg amount code 03 (+5)")
    else:
        fb.append("FAIL: Avg amount code 03 not found")

    if has_days:
        score += 5
        fb.append("PASS: 365 days on site (+5)")
    else:
        fb.append("FAIL: 365 days not found")

    # Check Storage Configurations
    tank = "above ground" in block or "aboveground" in block
    amb_p = "ambient pressure" in block
    amb_t = "ambient temperature" in block
    liquid = "liquid" in block
    loc = "chemical feed building 2" in block

    if tank:
        score += 5
        fb.append("PASS: Above ground tank (+5)")
    else:
        fb.append("FAIL: Above ground tank not found")

    if amb_p:
        score += 5
        fb.append("PASS: Ambient pressure (+5)")
    else:
        fb.append("FAIL: Ambient pressure not found")

    if amb_t:
        score += 5
        fb.append("PASS: Ambient temperature (+5)")
    else:
        fb.append("FAIL: Ambient temperature not found")

    if liquid:
        score += 5
        fb.append("PASS: Liquid physical state (+5)")
    else:
        fb.append("FAIL: Liquid state not found")

    if loc:
        score += 5
        fb.append("PASS: Location description correct (+5)")
    else:
        fb.append("FAIL: Location description incorrect")

    passed = score >= pass_threshold
    
    # Enforce Trade Secret as a hard requirement
    if passed and not has_ts:
        passed = False
        fb.append("CRITICAL FAIL: Trade Secret flag MUST be enabled to pass this task.")

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(fb)
    }