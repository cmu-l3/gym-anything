#!/usr/bin/env python3
"""Verifier for event_equipment_location_checkout task.

Scoring breakdown (100 points):
  C1: 'Main Auditorium' location created (10 pts)
  C2: 7 target assets assigned to Location instead of User (35 pts, 5 pts per asset)
  C3: Expected checkin date set to '2026-03-16' (20 pts, ~2.85 pts per asset)
  C4: Checkout note includes 'Global Tech Symposium' (20 pts, ~2.85 pts per asset)
  C5: Unrelated assets (AV-PROJ-03, AV-MIC-05) untouched (15 pts, 7.5 pts each)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/event_equipment_location_checkout_result.json"


def verify_event_equipment_location_checkout(traj, env_info, task_info):
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

    loc_found = result.get("location_found", False)
    loc_id = result.get("location_id", "")
    targets = result.get("targets", [])
    unrelated = result.get("unrelated", [])

    # --- Do-Nothing Gate ---
    any_checked_out = False
    for asset in targets + unrelated:
        assigned_to = asset.get("assigned_to")
        if assigned_to and assigned_to not in ["NULL", "", "0"]:
            any_checked_out = True
            break
            
    if not any_checked_out and not loc_found:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No location was created and no assets were checked out."}

    # --- C1: Location Created (10 pts) ---
    if loc_found:
        score += 10
        feedback.append("C1: 'Main Auditorium' Location created successfully (+10)")
    else:
        feedback.append("C1: 'Main Auditorium' Location not found (+0)")

    # Tracking per-asset accomplishments
    correct_assignments = 0
    correct_dates = 0
    correct_notes = 0
    num_targets = len(targets)

    # --- C2, C3, C4: Process Target Assets ---
    for asset in targets:
        tag = asset.get("tag")
        assigned_to = asset.get("assigned_to", "NULL")
        assigned_type = asset.get("assigned_type", "")
        expected_checkin = asset.get("expected_checkin", "")
        note = asset.get("note", "")

        # C2: Asset assigned to Location (Polymorphic Relation Check)
        is_assigned_to_loc = False
        if "Location" in assigned_type and assigned_to not in ["NULL", "", "0"]:
            # If the user created multiple locations, strictly enforce matching our loc_id if loc_found
            if loc_found and str(assigned_to) == str(loc_id):
                is_assigned_to_loc = True
            elif not loc_found:
                # If they misspelled the location name but checked it out to *a* location, give partial benefit
                is_assigned_to_loc = True

        if is_assigned_to_loc:
            correct_assignments += 1
        
        # C3: Checkin Date
        if "2026-03-16" in expected_checkin:
            correct_dates += 1
            
        # C4: Note
        if "GLOBAL TECH SYMPOSIUM" in note.upper():
            correct_notes += 1

    # Accumulate Target Scores
    assignment_score = int(35 * correct_assignments / num_targets) if num_targets else 0
    score += assignment_score
    feedback.append(f"C2: {correct_assignments}/{num_targets} target assets properly assigned to a Location (+{assignment_score})")

    dates_score = int(20 * correct_dates / num_targets) if num_targets else 0
    score += dates_score
    feedback.append(f"C3: {correct_dates}/{num_targets} target assets have expected check-in date 2026-03-16 (+{dates_score})")

    notes_score = int(20 * correct_notes / num_targets) if num_targets else 0
    score += notes_score
    feedback.append(f"C4: {correct_notes}/{num_targets} target assets have correct event note (+{notes_score})")

    # --- C5: Unrelated Assets Untouched (15 pts) ---
    untouched = 0
    num_unrelated = len(unrelated)
    for asset in unrelated:
        if asset.get("assigned_to", "NULL") in ["NULL", "", "0"]:
            untouched += 1
            
    unrelated_score = int(15 * untouched / num_unrelated) if num_unrelated else 0
    score += unrelated_score
    feedback.append(f"C5: {untouched}/{num_unrelated} unrelated assets left untouched (+{unrelated_score})")

    # Compute final pass state
    key_criteria_met = (correct_assignments >= 5) and loc_found
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }