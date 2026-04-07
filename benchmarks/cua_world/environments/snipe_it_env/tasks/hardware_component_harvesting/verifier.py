#!/usr/bin/env python3
"""Verifier for hardware_component_harvesting task.

Scoring Breakdown (100 points):
  C1 (10 pts): "Pending E-Waste" status label exists with type "archived".
  C2 (15 pts): Broken assets (TRG-001/002/003) have "Pending E-Waste" status (5 pts each).
  C3 (35 pts): Broken assets have 0 components attached (parts checked in) (~11.6 pts each).
  C4 (20 pts): Healthy assets (TRG-004/005) have location "Boston HQ" (10 pts each).
  C5 (20 pts): Healthy assets still have components attached (collateral damage check) (10 pts each).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)
RESULT_PATH = "/tmp/hardware_component_harvesting_result.json"

def verify_hardware_component_harvesting(traj, env_info, task_info):
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
    
    status_label = result.get("status_label", {})
    assets = result.get("assets", {})

    broken_tags = ["TRG-001", "TRG-002", "TRG-003"]
    healthy_tags = ["TRG-004", "TRG-005"]

    # --- Do-nothing check ---
    changed_state = False
    if status_label.get("exists"):
        changed_state = True
    for tag in broken_tags:
        a = assets.get(tag, {})
        if a.get("found") and a.get("comp_count", 2) < 2:
            changed_state = True
    for tag in healthy_tags:
        a = assets.get(tag, {})
        if a.get("found") and a.get("location") == "Boston HQ":
            changed_state = True

    if not changed_state:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No changes were detected."}

    # --- C1: Status Label (10 pts) ---
    if status_label.get("exists"):
        if status_label.get("type", "").lower() == "archived":
            score += 10
            feedback.append("C1: 'Pending E-Waste' status label created and is Archived (+10)")
        else:
            score += 5
            feedback.append(f"C1: 'Pending E-Waste' exists but type is '{status_label.get('type')}', not Archived (+5)")
    else:
        feedback.append("C1: 'Pending E-Waste' status label was not created (+0)")

    # --- C2: Broken Assets Status (15 pts) ---
    c2_score = 0
    for tag in broken_tags:
        a = assets.get(tag, {})
        if a.get("found"):
            if a.get("status_name", "").lower() == "pending e-waste":
                c2_score += 5
                feedback.append(f"C2: {tag} status updated correctly (+5)")
            else:
                feedback.append(f"C2: {tag} status is '{a.get('status_name')}', expected 'Pending E-Waste' (+0)")
        else:
            feedback.append(f"C2: {tag} not found (+0)")
    score += c2_score

    # --- C3: Component Harvesting (35 pts) ---
    c3_total = 0
    c3_alloc = [12, 12, 11] # Distribute 35 points across the 3 assets
    for i, tag in enumerate(broken_tags):
        a = assets.get(tag, {})
        if a.get("found"):
            comp_count = int(a.get("comp_count", 2))
            if comp_count == 0:
                c3_total += c3_alloc[i]
                feedback.append(f"C3: {tag} components successfully harvested (+{c3_alloc[i]})")
            else:
                feedback.append(f"C3: {tag} still has {comp_count} components attached (+0)")
    score += c3_total

    # --- C4: Healthy Assets Relocation (20 pts) ---
    c4_score = 0
    for tag in healthy_tags:
        a = assets.get(tag, {})
        if a.get("found"):
            if a.get("location") == "Boston HQ":
                c4_score += 10
                feedback.append(f"C4: {tag} relocated to Boston HQ (+10)")
            else:
                feedback.append(f"C4: {tag} location is '{a.get('location')}', expected 'Boston HQ' (+0)")
        else:
            feedback.append(f"C4: {tag} not found (+0)")
    score += c4_score

    # --- C5: Healthy Assets Preserved (20 pts) ---
    c5_score = 0
    for tag in healthy_tags:
        a = assets.get(tag, {})
        if a.get("found"):
            comp_count = int(a.get("comp_count", 0))
            if comp_count > 0:
                c5_score += 10
                feedback.append(f"C5: {tag} components correctly preserved ({comp_count} attached) (+10)")
            else:
                feedback.append(f"C5: {tag} components were incorrectly harvested/checked in (+0)")
    score += c5_score

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }