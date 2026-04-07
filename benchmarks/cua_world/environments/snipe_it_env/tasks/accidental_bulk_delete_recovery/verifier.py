#!/usr/bin/env python3
"""
Verifier for accidental_bulk_delete_recovery task.

Scoring breakdown (100 points):
  C1: The 3 Switches are restored (deleted_at is null) (30 pts, 10 each)
  C2: The Laptop is intentionally left deleted (deleted_at is not null) (15 pts)
  C3: Switches checked out to a Location Entity type (15 pts, 5 each)
  C4: Switches checked out to MDF - Data Center ID (25 pts, ~8.3 each)
  C5: "Restored after accidental deletion incident" in checkout notes (15 pts, 5 each)
  
Pass Threshold: >=80 points AND C1 & C2 perfectly met.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/accidental_bulk_delete_recovery_result.json"

def verify_recovery(traj, env_info, task_info):
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

    mdf_id = str(result.get("mdf_location_id", "0"))
    
    switches = [
        result.get("sw_core_01", {}),
        result.get("sw_core_02", {}),
        result.get("sw_dist_01", {})
    ]
    laptop = result.get("lapt_old_99", {})

    # --- Prevent do-nothing & blind restore-all ---
    restored_switches = sum(1 for sw in switches if sw.get("found") and not sw.get("is_deleted"))
    laptop_deleted = laptop.get("found") and laptop.get("is_deleted")

    if restored_switches == 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No switches were restored."}
    
    # --- C1: Switches Restored (30 pts) ---
    if restored_switches == 3:
        score += 30
        feedback.append("C1: All 3 switches correctly restored (+30)")
    else:
        score += (restored_switches * 10)
        feedback.append(f"C1: {restored_switches}/3 switches restored (+{restored_switches * 10})")

    # --- C2: Laptop Left Deleted (15 pts) ---
    if laptop_deleted:
        score += 15
        feedback.append("C2: E-waste laptop correctly left in deleted state (+15)")
    else:
        feedback.append("C2: E-waste laptop was wrongly restored (+0)")

    # Analyze individual switch properties
    location_type_count = 0
    mdf_assigned_count = 0
    correct_notes_count = 0

    for sw in switches:
        if not sw.get("found") or sw.get("is_deleted"):
            continue
            
        tag = sw.get("tag", "Unknown")
        assigned_type = str(sw.get("assigned_type", ""))
        assigned_to = str(sw.get("assigned_to", "NULL"))
        note = str(sw.get("note", "")).upper()

        # --- C3: Checked out to Location Entity ---
        # Snipe-IT stores Location assignment type as App\Models\Location
        if "LOCATION" in assigned_type.upper():
            location_type_count += 1
        
        # --- C4: Checked out to MDF - Data Center ---
        if assigned_to == mdf_id and mdf_id != "0":
            mdf_assigned_count += 1
            
        # --- C5: Correct Note ---
        if "RESTORED AFTER ACCIDENTAL DELETION INCIDENT" in note:
            correct_notes_count += 1

    # Score C3
    if location_type_count == 3:
        score += 15
        feedback.append("C3: All 3 switches correctly checked out to a Location entity type (+15)")
    else:
        score += (location_type_count * 5)
        feedback.append(f"C3: {location_type_count}/3 switches checked out to a Location entity (+{location_type_count * 5})")

    # Score C4
    if mdf_assigned_count == 3:
        score += 25
        feedback.append("C4: All 3 switches correctly checked out to MDF Data Center (+25)")
    else:
        # Give ~8.3 points each
        c4_pts = int(mdf_assigned_count * 8.33)
        score += c4_pts
        feedback.append(f"C4: {mdf_assigned_count}/3 switches checked out to MDF Data Center (+{c4_pts})")

    # Score C5
    if correct_notes_count == 3:
        score += 15
        feedback.append("C5: All 3 switches have the correct checkout note (+15)")
    else:
        score += (correct_notes_count * 5)
        feedback.append(f"C5: {correct_notes_count}/3 switches have correct checkout note (+{correct_notes_count * 5})")

    # Pass logic: Must have >=80 points, and core constraints (C1 & C2) must be perfectly met
    c1_c2_met = (restored_switches == 3 and laptop_deleted)
    passed = (score >= 80) and c1_c2_met

    if not c1_c2_met:
        feedback.append("FAILED: Critical constraints (restoring all switches while leaving the laptop deleted) were not met.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }