#!/usr/bin/env python3
"""
Verifier for record_vitals task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_vitals(traj, env_info, task_info):
    """
    Verify that patient vitals were recorded correctly.
    
    Expected Vitals:
    - BP: 138/88 (Tol: +/- 2)
    - HR: 76 (Tol: +/- 1)
    - WT: 72.5 (Tol: +/- 0.5)
    - HT: 165 (Tol: +/- 1)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    new_measurements = result.get("new_measurements", [])
    initial_count = result.get("initial_count", 0)
    current_count = result.get("current_count", 0)
    
    # Organize measurements by type for easier checking
    # Measurements table 'type' column: BP, HR, WT, HT
    # Note: Oscar might store Weight as 'WT' or 'Weight', Height as 'HT' or 'Height'.
    # We'll normalize to standard keys.
    vitals_found = {}
    
    for m in new_measurements:
        m_type = m.get("type", "").upper()
        m_val = m.get("value", "")
        
        # Normalize keys based on common Oscar values
        if m_type == "BP": key = "BP"
        elif m_type in ["HR", "PULSE"]: key = "HR"
        elif m_type in ["WT", "WEIGHT"]: key = "WT"
        elif m_type in ["HT", "HEIGHT"]: key = "HT"
        else: key = m_type
        
        # Keep the most recent value if multiple
        if key not in vitals_found:
            vitals_found[key] = m_val

    score = 0
    feedback = []
    
    # 3. Verify Specific Vitals
    
    # Blood Pressure (20 pts)
    # Expected: 138/88
    bp_val = vitals_found.get("BP")
    if bp_val:
        try:
            sys_str, dia_str = bp_val.split("/")
            sys_val = float(sys_str)
            dia_val = float(dia_str)
            
            if (136 <= sys_val <= 140) and (86 <= dia_val <= 90):
                score += 20
                feedback.append(f"BP Correct ({bp_val})")
            else:
                score += 5 # Partial credit for format correctness
                feedback.append(f"BP value out of range: {bp_val} (Expected 138/88)")
        except:
            feedback.append(f"BP format invalid: {bp_val}")
    else:
        feedback.append("BP missing")

    # Heart Rate (20 pts)
    # Expected: 76
    hr_val = vitals_found.get("HR")
    if hr_val:
        try:
            hr_float = float(hr_val)
            if 75 <= hr_float <= 77:
                score += 20
                feedback.append(f"HR Correct ({hr_val})")
            else:
                score += 5
                feedback.append(f"HR value out of range: {hr_val} (Expected 76)")
        except:
            feedback.append(f"HR format invalid: {hr_val}")
    else:
        feedback.append("HR missing")

    # Weight (20 pts)
    # Expected: 72.5
    wt_val = vitals_found.get("WT")
    if wt_val:
        try:
            wt_float = float(wt_val)
            if 72.0 <= wt_float <= 73.0:
                score += 20
                feedback.append(f"Weight Correct ({wt_val})")
            else:
                score += 5
                feedback.append(f"Weight value out of range: {wt_val} (Expected 72.5)")
        except:
            feedback.append(f"Weight format invalid: {wt_val}")
    else:
        feedback.append("Weight missing")

    # Height (20 pts)
    # Expected: 165
    ht_val = vitals_found.get("HT")
    if ht_val:
        try:
            ht_float = float(ht_val)
            if 164 <= ht_float <= 166:
                score += 20
                feedback.append(f"Height Correct ({ht_val})")
            else:
                score += 5
                feedback.append(f"Height value out of range: {ht_val} (Expected 165)")
        except:
            feedback.append(f"Height format invalid: {ht_val}")
    else:
        feedback.append("Height missing")

    # 4. Anti-Gaming / Process Checks (20 pts)
    # Check that database count actually increased
    if current_count >= initial_count + 4:
        score += 10
        feedback.append("Database record count increased appropriately")
    elif current_count > initial_count:
        score += 5
        feedback.append("Database record count increased, but fewer than 4 records")
    else:
        feedback.append("No new database records found")
        
    # Browser check
    if result.get("browser_running"):
        score += 10
        feedback.append("Browser verified running")
    else:
        feedback.append("Browser was closed (unexpected)")

    # 5. VLM Check (Optional but good for robust verification)
    # If we had VLM here, we would check the final screenshot for the Measurements table.
    # For now, relying on DB verification is strong enough for this task type.

    # 6. Final Status
    passed = (score >= 60) and (current_count > initial_count)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }