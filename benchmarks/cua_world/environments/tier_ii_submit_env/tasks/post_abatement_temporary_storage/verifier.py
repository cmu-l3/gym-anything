#!/usr/bin/env python3
import json
import os
import tempfile

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\post_abatement_temporary_storage_result.json"

def verify_post_abatement_temporary_storage(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 70)

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read/parse result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found at expected path (do-nothing)."}

    score = 0
    fb = []

    # File Existence (20 pts)
    score += 20
    fb.append("PASS: Submission file created (+20)")

    # Chemical Identity (20 pts)
    chem_name = result.get("chemical_name", "")
    cas_num = result.get("cas_number", "")
    if "Sodium Hydroxide" in chem_name and "1310-73-2" in cas_num:
        score += 20
        fb.append("PASS: Chemical Sodium Hydroxide (1310-73-2) found (+20)")
    else:
        fb.append(f"FAIL: Expected Sodium Hydroxide (1310-73-2), found '{chem_name}' ('{cas_num}')")

    # Timeframe Accuracy (30 pts)
    days = str(result.get("days_on_site", "")).strip()
    if days == "90":
        score += 30
        fb.append("PASS: Days on site is exactly 90 (+30)")
    else:
        fb.append(f"FAIL: Days on site is '{days}' (expected 90)")

    # Attachment Included (15 pts)
    att_name = result.get("attachment_name", "")
    if att_name.endswith(".pdf"):
        score += 15
        fb.append(f"PASS: PDF Attachment found ({att_name}) (+15)")
    else:
        fb.append("FAIL: No PDF attachment found in submission")

    # Hazard Classification (15 pts)
    hazards = result.get("hazards", [])
    expected_hazards = [
        "Corrosive to metal",
        "Skin corrosion or irritation",
        "Serious eye damage or eye irritation"
    ]
    missing = [h for h in expected_hazards if h not in hazards]
    if not missing:
        score += 15
        fb.append("PASS: All required hazards flagged (+15)")
    else:
        fb.append(f"FAIL: Missing hazards: {missing}")

    # Strict requirement: Timeframe MUST be 90
    key_criteria_met = (days == "90")
    passed = (score >= pass_threshold) and key_criteria_met

    if not key_criteria_met:
        fb.append("CRITICAL FAIL: Timeframe (Days on site) was not changed to 90.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb),
    }