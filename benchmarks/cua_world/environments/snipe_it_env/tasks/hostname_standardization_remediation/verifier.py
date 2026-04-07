#!/usr/bin/env python3
"""
Verifier for hostname_standardization_remediation task.

Scoring breakdown (100 points):
  C1: Asset ASSET-8001 renamed correctly (20 pts)
  C2: Asset ASSET-8002 renamed correctly (20 pts)
  C3: Asset ASSET-8003 renamed correctly (20 pts)
  C4: Asset ASSET-8004 renamed correctly (20 pts)
  C5: Negative Constraint: Marketing assets left completely unmodified (10 pts)
  C6: Negative Constraint: Unassigned assets left completely unmodified (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/hostname_standardization_result.json"

def verify_hostname_standardization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable."}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result state: {e}"}

    task_start = int(result.get('task_start_time', 0))
    assets = result.get('assets', {})
    
    score = 0
    feedback = []

    # Map of target assets and their expected standard ZTNA hostnames
    expected_renames = {
        "ASSET-8001": ("LON-ENG-ASSET-8001", 20, "C1: London Eng Asset 1"),
        "ASSET-8002": ("LON-ENG-ASSET-8002", 20, "C2: London Eng Asset 2"),
        "ASSET-8003": ("BER-ENG-ASSET-8003", 20, "C3: Berlin Eng Asset"),
        "ASSET-8004": ("TYO-ENG-ASSET-8004", 20, "C4: Tokyo Eng Asset")
    }

    # "Do Nothing" anti-gaming gate
    changed_in_scope = 0
    for tag, (exp_name, _, _) in expected_renames.items():
        if assets.get(tag, {}).get("name") == exp_name:
            changed_in_scope += 1

    if changed_in_scope == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "DO-NOTHING: No target assets were successfully renamed to the required format."
        }

    # Evaluate C1 - C4: Target Asset Modifications
    for tag, (expected_name, pts, crit_name) in expected_renames.items():
        asset = assets.get(tag, {})
        if not asset.get("found"):
            feedback.append(f"{crit_name} - {tag} not found in database (+0)")
            continue

        current_name = asset.get("name", "")
        updated_at = asset.get("updated_at", 0)
        
        if current_name == expected_name:
            # Timestamp check allows a 2 second buffer around task generation time to prevent strict DB sync issues
            if updated_at >= (task_start - 2):
                score += pts
                feedback.append(f"{crit_name} - {tag} correctly renamed to {expected_name} (+{pts})")
            else:
                feedback.append(f"{crit_name} - {tag} has correct name but was modified BEFORE task started (Gaming detected) (+0)")
        else:
            feedback.append(f"{crit_name} - {tag} name is '{current_name}', expected exactly '{expected_name}' (+0)")

    # Evaluate C5: Scope Restriction (Marketing Dept)
    c5_passed = True
    for tag, legacy_name in [("ASSET-8005", "Eve-Air"), ("ASSET-8006", "Frank-Surface")]:
        asset = assets.get(tag, {})
        current_name = asset.get("name", "")
        if current_name != legacy_name:
            c5_passed = False
            feedback.append(f"Violation (C5): Marketing asset {tag} was improperly modified from '{legacy_name}' to '{current_name}'")

    if c5_passed:
        score += 10
        feedback.append("C5: Marketing department assets correctly left unmodified (+10)")

    # Evaluate C6: Scope Restriction (Unassigned Ready to Deploy state)
    c6_passed = True
    for tag, legacy_name in [("ASSET-8007", "Spare-Eng-Laptop")]:
        asset = assets.get(tag, {})
        current_name = asset.get("name", "")
        if current_name != legacy_name:
            c6_passed = False
            feedback.append(f"Violation (C6): Unassigned asset {tag} was improperly modified from '{legacy_name}' to '{current_name}'")

    if c6_passed:
        score += 10
        feedback.append("C6: Unassigned assets correctly left unmodified (+10)")

    # Pass condition requires at least 80 points (Must successfully complete renaming, while constraints enforce deduction prevention)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }