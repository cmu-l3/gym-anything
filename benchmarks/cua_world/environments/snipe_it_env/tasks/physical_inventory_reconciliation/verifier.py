#!/usr/bin/env python3
"""Verifier for physical_inventory_reconciliation task.

Scoring breakdown (100 points):
  C1: AUD01 audited (10 pts)
  C2: AUD02 location updated to Building B (15 pts)
  C3: AUD02 audited (5 pts)
  C4: AUD03 status changed to Lost/Stolen (15 pts)
  C5: AUD04 audited (10 pts)
  C6: AUD05 status changed to Lost/Stolen (15 pts)
  C7: Missing asset notes present on AUD03 & AUD05 (10 pts)
  C8: New asset AUD06 created with correct model, serial, and location (15 pts)
  C9: No collateral damage (count matches expected) (5 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/physical_inventory_result.json"

def verify_physical_inventory_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    start_time = int(result.get("task_start_time", 0))
    loc_b_id = str(result.get("loc_b_id", ""))
    sl_lost_id = str(result.get("sl_lost_id", ""))
    mod_cisco_id = str(result.get("mod_cisco_id", ""))
    
    assets = result.get("assets", {})
    aud01 = assets.get("AUD01", {})
    aud02 = assets.get("AUD02", {})
    aud03 = assets.get("AUD03", {})
    aud04 = assets.get("AUD04", {})
    aud05 = assets.get("AUD05", {})
    aud06 = result.get("aud06", {})

    # Allow 5 seconds of clock skew for timestamps
    valid_audit_time = start_time - 5

    # --- Do-Nothing Gate ---
    if not aud06.get("found") and aud01.get("last_audit_ts", 0) < valid_audit_time and str(aud03.get("status_id")) != sl_lost_id:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No assets audited, modified, or created."}

    # --- C1: AUD01 audited (10 pts) ---
    if aud01.get("found") and aud01.get("last_audit_ts", 0) >= valid_audit_time:
        score += 10
        feedback.append("C1: ASSET-AUD01 successfully marked as audited (+10)")
    else:
        feedback.append("C1: ASSET-AUD01 was not audited (+0)")

    # --- C2 & C3: AUD02 relocated and audited (15 + 5 pts) ---
    if aud02.get("found"):
        if str(aud02.get("rtd_location_id")) == loc_b_id:
            score += 15
            feedback.append("C2: ASSET-AUD02 successfully relocated to Building B (+15)")
        else:
            feedback.append("C2: ASSET-AUD02 not relocated to Building B (+0)")
            
        if aud02.get("last_audit_ts", 0) >= valid_audit_time:
            score += 5
            feedback.append("C3: ASSET-AUD02 successfully marked as audited (+5)")
        else:
            feedback.append("C3: ASSET-AUD02 was not audited (+0)")
    else:
        feedback.append("C2/C3: ASSET-AUD02 not found (+0)")

    # --- C4: AUD03 status changed to Lost/Stolen (15 pts) ---
    if aud03.get("found") and str(aud03.get("status_id")) == sl_lost_id:
        score += 15
        feedback.append("C4: ASSET-AUD03 status correctly changed to Lost/Stolen (+15)")
    else:
        feedback.append("C4: ASSET-AUD03 status not changed to Lost/Stolen (+0)")

    # --- C5: AUD04 audited (10 pts) ---
    if aud04.get("found") and aud04.get("last_audit_ts", 0) >= valid_audit_time:
        score += 10
        feedback.append("C5: ASSET-AUD04 successfully marked as audited (+10)")
    else:
        feedback.append("C5: ASSET-AUD04 was not audited (+0)")

    # --- C6: AUD05 status changed to Lost/Stolen (15 pts) ---
    if aud05.get("found") and str(aud05.get("status_id")) == sl_lost_id:
        score += 15
        feedback.append("C6: ASSET-AUD05 status correctly changed to Lost/Stolen (+15)")
    else:
        feedback.append("C6: ASSET-AUD05 status not changed to Lost/Stolen (+0)")

    # --- C7: Missing asset notes present on AUD03 & AUD05 (10 pts) ---
    notes_score = 0
    keywords = ["not found", "physical inventory"]
    
    aud03_all_notes = (aud03.get("notes", "") + " " + aud03.get("log_notes", "")).lower()
    aud05_all_notes = (aud05.get("notes", "") + " " + aud05.get("log_notes", "")).lower()

    if any(k in aud03_all_notes for k in keywords):
        notes_score += 5
    else:
        feedback.append("C7a: ASSET-AUD03 missing correct audit note (-5)")
        
    if any(k in aud05_all_notes for k in keywords):
        notes_score += 5
    else:
        feedback.append("C7b: ASSET-AUD05 missing correct audit note (-5)")
        
    score += notes_score
    if notes_score == 10:
        feedback.append("C7: Both lost assets have appropriate audit notes (+10)")

    # --- C8: New asset AUD06 created correctly (15 pts) ---
    c8_score = 0
    if aud06.get("found"):
        c8_score += 5
        feedback.append("C8a: ASSET-AUD06 created (+5)")
        
        if aud06.get("serial") == "CBW2413A0KP":
            c8_score += 5
            feedback.append("C8b: ASSET-AUD06 serial number correct (+5)")
        else:
            feedback.append(f"C8b: ASSET-AUD06 incorrect serial: {aud06.get('serial')} (+0)")
            
        if str(aud06.get("model_id")) == mod_cisco_id and str(aud06.get("loc_id")) == loc_b_id:
            c8_score += 5
            feedback.append("C8c: ASSET-AUD06 model and location correct (+5)")
        else:
            feedback.append("C8c: ASSET-AUD06 incorrect model or location (+0)")
    else:
        feedback.append("C8: ASSET-AUD06 not found (+0)")
    score += c8_score

    # --- C9: No collateral damage (5 pts) ---
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    
    # We expect exactly 1 new asset (AUD06)
    if current_count == initial_count + 1:
        score += 5
        feedback.append("C9: Exact expected asset count achieved (no collateral damage) (+5)")
    else:
        feedback.append(f"C9: Unintended asset count changes (expected {initial_count + 1}, got {current_count}) (+0)")

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }