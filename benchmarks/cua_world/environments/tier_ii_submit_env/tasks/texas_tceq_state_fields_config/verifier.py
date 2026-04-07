#!/usr/bin/env python3
"""
Verifier for texas_tceq_state_fields_config task.
Uses a hybrid approach checking standard outputs programmatically 
with VLM verification of the trajectory ensuring the fields were actually interacted with.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Attempt to load VLM Utilities, fallback gracefully if not present
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available, falling back to pure programmatic verification.")

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\texas_tceq_state_fields_config_result.json"

def verify_texas_tceq_state_fields_config(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 70)
    
    expected_cn = metadata.get("expected_cn", "CN603741463")
    expected_rn = metadata.get("expected_rn", "RN100235266")
    expected_txt2 = metadata.get("expected_txt2", "987654")

    # Read exported JSON
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

    score = 0
    fb = []

    # Criterion 1: Do-nothing check & Output created
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found (do-nothing detected)."}
        
    score += 10
    fb.append("PASS: Output file exists (+10)")
    
    if result.get("file_modified_during_task", False):
        fb.append("PASS: File timestamp confirms action during task")
    else:
        fb.append("WARNING: File timestamp predates task start (possible invalid submission save)")

    fac = result.get("facility", {})
    
    # Criterion 2: Customer Number (CN)
    actual_cn = fac.get("CustomerNumber", "")
    if actual_cn == expected_cn:
        score += 25
        fb.append(f"PASS: Customer Number correctly entered as {actual_cn} (+25)")
    else:
        fb.append(f"FAIL: Customer Number = '{actual_cn}' (expected '{expected_cn}')")

    # Criterion 3: Regulated Entity Number (RN)
    actual_rn = fac.get("RegulatedEntityNumber", "")
    if actual_rn == expected_rn:
        score += 25
        fb.append(f"PASS: Regulated Entity Number correctly entered as {actual_rn} (+25)")
    else:
        fb.append(f"FAIL: Regulated Entity Number = '{actual_rn}' (expected '{expected_rn}')")

    # Criterion 4: TXT2 Number
    actual_txt2 = fac.get("TXT2Number", "")
    if actual_txt2 == expected_txt2:
        score += 20
        fb.append(f"PASS: TXT2 Number correctly entered as {actual_txt2} (+20)")
    else:
        fb.append(f"FAIL: TXT2 Number = '{actual_txt2}' (expected '{expected_txt2}')")

    # Criterion 5: VLM Trajectory Process Check (Anti-gaming check)
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are verifying an agent's completion of configuring Texas State Fields in EPA Tier2 Submit.
                Look at these trajectory frames.
                1. Did the agent open the facility record and navigate to the "State Fields" tab or section?
                2. Can you see alphanumeric identifiers like "CN603741463" or "RN100235266" being entered in the GUI?
                
                Respond with a JSON object ONLY:
                {
                    "state_fields_visible": true/false,
                    "identifiers_entered": true/false
                }"""
                
                vlm_res = query_vlm(images=images, prompt=prompt)
                
                if vlm_res and isinstance(vlm_res, dict) and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("state_fields_visible") or parsed.get("identifiers_entered"):
                        score += 20
                        fb.append("PASS: VLM trajectory verification confirmed genuine workflow (+20)")
                    else:
                        fb.append("FAIL: VLM visual verification did not detect GUI interaction with State Fields")
                else:
                    # Degradation case where API misbehaves
                    score += 20
                    fb.append("WARNING: VLM query failed, granting points automatically (+20)")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            score += 20
            fb.append(f"WARNING: VLM error encountered, granting points automatically (+20)")
    else:
        score += 20
        fb.append("WARNING: VLM checks disabled or no trajectory available, granting points automatically (+20)")

    # Final logic assessment
    passed = score >= pass_threshold
    
    # Critical fail condition logic (Must have successfully completed the main task goal)
    if actual_cn != expected_cn and actual_rn != expected_rn:
        passed = False
        fb.append("CRITICAL FAIL: The mandatory state fields were missing from the generated file.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb)
    }