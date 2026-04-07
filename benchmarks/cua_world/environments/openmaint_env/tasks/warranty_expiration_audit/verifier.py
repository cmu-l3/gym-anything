#!/usr/bin/env python3
"""
Verifier for warranty_expiration_audit task.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_warranty_expiration_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    
    # 1. Retrieve result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/war_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve result from environment: {e}"
        }

    assets_state = result.get("assets_state", {})
    found_wos = result.get("found_wos", [])
    contam_initial = result.get("contam_initial", {})

    score = 0
    feedback = []

    # --- C1: Renewal Notes (25 pts) ---
    # Expected: WAR-HVAC-001 (2027-03-01), WAR-HVAC-002 (2027-04-15), WAR-ELEV-001 (2028-02-28)
    renewal_targets = [
        ("WAR-HVAC-001", "2027-03-01"),
        ("WAR-HVAC-002", "2027-04-15"),
        ("WAR-ELEV-001", "2028-02-28")
    ]
    
    c1_score = 0
    for code, date_str in renewal_targets:
        state = assets_state.get(code, {})
        text = (state.get("Description", "") + " " + state.get("Notes", "")).lower()
        if date_str in text:
            c1_score += 1
        else:
            feedback.append(f"Missing renewal date {date_str} for {code}.")
    
    score += (c1_score / 3) * 25
    
    # --- C2: Work Orders Created (25 pts) ---
    # Expected: WOs for WAR-GEN-001 and WAR-ELEC-003
    wo_targets = ["WAR-GEN-001", "WAR-ELEC-003"]
    found_targets = set()
    high_priority_count = 0
    
    for wo in found_wos:
        target = wo.get("Target")
        if target in wo_targets:
            found_targets.add(target)
            # Check Priority (C3)
            prio = str(wo.get("Priority", "")).lower()
            if any(x in prio for x in ["high", "urgent", "critical", "1", "2"]):
                high_priority_count += 1
    
    c2_score = (len(found_targets) / 2) * 25
    score += c2_score
    if len(found_targets) < 2:
        feedback.append(f"Missing Work Orders for: {set(wo_targets) - found_targets}")

    # --- C3: WO Priority (10 pts) ---
    # Only verify priority if WOs exist
    if len(found_wos) > 0:
        c3_score = (high_priority_count / len(found_wos)) * 10
        score += c3_score
        if high_priority_count < len(found_wos):
            feedback.append("Some Work Orders did not have 'High' priority.")
    
    # --- C4: Out of Warranty (15 pts) ---
    # Expected: WAR-ELEC-001 has "OUT OF WARRANTY"
    elec_state = assets_state.get("WAR-ELEC-001", {})
    elec_text = (elec_state.get("Description", "") + " " + elec_state.get("Notes", "")).lower()
    if "out of warranty" in elec_text:
        score += 15
    else:
        feedback.append("WAR-ELEC-001 not marked as 'OUT OF WARRANTY'.")

    # --- C5: Contamination Trap (25 pts) ---
    # WAR-PUMP-002 should match initial state roughly
    pump_state = assets_state.get("WAR-PUMP-002", {})
    # Simple check: Notes should contain original text and NOT contain today's modification or wrong dates
    # Original: "WARRANTY RENEWED through 2028-12-31 — Vendor maintenance agreement"
    
    pump_current_notes = (pump_state.get("Notes", "") or pump_state.get("Description", ""))
    pump_initial_notes = contam_initial.get("Notes", "")
    
    # Normalize for comparison (ignore whitespace differences)
    norm_current = " ".join(pump_current_notes.split())
    norm_initial = " ".join(pump_initial_notes.split())
    
    if norm_current == norm_initial and pump_state.get("_is_active", True):
        score += 25
    else:
        feedback.append("Contamination trap triggered: WAR-PUMP-002 was modified.")
        # Apply score cap
        score = min(score, 50)

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " ".join(feedback) if feedback else "All tasks completed successfully."
    }