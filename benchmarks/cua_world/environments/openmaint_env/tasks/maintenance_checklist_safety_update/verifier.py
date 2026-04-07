#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_maintenance_checklist_safety_update(traj, env_info, task_info):
    """
    Verifies that the OpenMaint PM records were updated according to the safety directive.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Retrieve result file
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/task_result.json", local_path)
        with open(local_path) as f:
            data = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

    current = data.get("current", {})
    baseline = data.get("baseline", {})
    
    score = 0
    feedback = []

    # 1. Check Chiller (PM-CHILLER-01)
    # Req: Add "Lockout/Tagout" warning, Duration -> 240
    chiller = current.get("PM-CHILLER-01", {})
    chiller_base = baseline.get("PM-CHILLER-01", {})
    
    if not chiller.get("exists"):
        feedback.append("PM-CHILLER-01 deleted!")
    else:
        desc = chiller.get("description", "").lower()
        dur = chiller.get("duration", 0)
        
        c1_text = "lockout" in desc or "tagout" in desc or "loto" in desc
        c1_time = (dur == 240)
        
        if c1_text: 
            score += 12.5
            feedback.append("Chiller description updated.")
        else:
            feedback.append("Chiller description missing 'Lockout/Tagout'.")
            
        if c1_time:
            score += 12.5
            feedback.append("Chiller duration correct (240).")
        else:
            feedback.append(f"Chiller duration incorrect (found {dur}, expected 240).")

    # 2. Check Boiler (PM-BOILER-01)
    # Req: "Verify pressure is between 20-25 PSI"
    boiler = current.get("PM-BOILER-01", {})
    if not boiler.get("exists"):
        feedback.append("PM-BOILER-01 deleted!")
    else:
        desc = boiler.get("description", "").lower()
        c2_text = "20-25" in desc or ("20" in desc and "25" in desc and "psi" in desc)
        
        if c2_text:
            score += 25
            feedback.append("Boiler description correct.")
        else:
            feedback.append("Boiler description missing '20-25 PSI' info.")

    # 3. Check Elec (PM-ELEC-01)
    # Req: "Wear Arc Flash PPE Category 4", Duration -> 90
    elec = current.get("PM-ELEC-01", {})
    if not elec.get("exists"):
        feedback.append("PM-ELEC-01 deleted!")
    else:
        desc = elec.get("description", "").lower()
        dur = elec.get("duration", 0)
        
        c3_text = "ppe" in desc and "category 4" in desc
        c3_time = (dur == 90)
        
        if c3_text:
            score += 12.5
            feedback.append("Electrical PPE req added.")
        else:
            feedback.append("Electrical description missing 'PPE Category 4'.")
            
        if c3_time:
            score += 12.5
            feedback.append("Electrical duration correct (90).")
        else:
            feedback.append(f"Electrical duration incorrect (found {dur}, expected 90).")

    # 4. Check Contamination (PM-AHU-02)
    # Req: UNCHANGED
    ahu = current.get("PM-AHU-02", {})
    ahu_base = baseline.get("PM-AHU-02", {})
    
    if not ahu.get("exists"):
        feedback.append("Contamination trap: PM-AHU-02 was deleted!")
    else:
        # Check for modification
        desc_changed = ahu.get("description") != ahu_base.get("description")
        dur_changed = ahu.get("duration") != ahu_base.get("duration")
        
        if not desc_changed and not dur_changed:
            score += 25
            feedback.append("Contamination trap passed (PM-AHU-02 unchanged).")
        else:
            feedback.append(f"Contamination trap failed: PM-AHU-02 was modified (Desc changed: {desc_changed}, Dur changed: {dur_changed}).")

    # Anti-gaming: Do-nothing check
    # If the current state matches baseline exactly for ALL records, score is 0
    all_unchanged = True
    for code in ["PM-CHILLER-01", "PM-BOILER-01", "PM-ELEC-01"]:
        curr = current.get(code, {})
        base = baseline.get(code, {})
        if curr.get("description") != base.get("description") or curr.get("duration") != base.get("duration"):
            all_unchanged = False
            break
            
    if all_unchanged:
        score = 0
        feedback = ["DO-NOTHING DETECTED: No changes made to target records."]

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }