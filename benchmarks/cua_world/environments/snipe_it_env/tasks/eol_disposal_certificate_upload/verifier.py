#!/usr/bin/env python3
"""
Verifier for eol_disposal_certificate_upload task.
Verifies status label creation, asset status modification, and file attachments.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)
RESULT_PATH = "/tmp/eol_disposal_result.json"

def verify_eol_disposal_certificate_upload(traj, env_info, task_info):
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

    # C1: Status Label Created (15 pts)
    label_info = result.get("status_label", {})
    if label_info.get("exists"):
        l_type = label_info.get("type", "").lower()
        if l_type == "archived":
            score += 15
            feedback.append("C1: Status label 'Destroyed - Verified' created and is type Archived (+15)")
        else:
            score += 7
            feedback.append(f"C1: Status label created but wrong type ('{l_type}', expected 'archived') (+7)")
    else:
        feedback.append("C1: Status label 'Destroyed - Verified' not found (+0)")

    assets = result.get("assets", {})
    targets = ["HD-DISP-001", "HD-DISP-002", "HD-DISP-003", "HD-DISP-004"]
    
    # C2: Assets 1-4 status changed (20 pts - 5 each)
    # C3: Assets 1-4 files attached (45 pts - 11.25 each)
    c2_score = 0
    c3_score = 0
    
    for tag in targets:
        asset = assets.get(tag, {})
        if not asset.get("found"):
            feedback.append(f"{tag} not found")
            continue
            
        status_name = asset.get("status_name", "")
        if status_name == "Destroyed - Verified":
            c2_score += 5
        
        if asset.get("has_file"):
            c3_score += 11.25
            
    score += c2_score
    score += c3_score
    feedback.append(f"C2: {int(c2_score/5)}/4 assets changed to correct status (+{c2_score})")
    feedback.append(f"C3: {int(c3_score/11.25)}/4 assets have files attached (+{c3_score})")

    # C4: Control asset untouched (10 pts)
    asset5 = assets.get("HD-DISP-005", {})
    if asset5.get("found"):
        if asset5.get("status_name") == "Pending Disposal" and not asset5.get("has_file"):
            score += 10
            feedback.append("C4: Control asset HD-DISP-005 left unmodified (+10)")
        else:
            feedback.append("C4: Control asset HD-DISP-005 was wrongly modified (+0)")
    else:
        feedback.append("C4: Control asset HD-DISP-005 not found (+0)")

    # C5: No unintended changes (10 pts)
    unintended = result.get("unintended_changes", 0)
    if unintended == 0:
        score += 10
        feedback.append("C5: No unintended assets moved to Destroyed - Verified (+10)")
    else:
        feedback.append(f"C5: {unintended} unintended assets moved to Destroyed - Verified (+0)")

    passed = score >= 75
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback)
    }