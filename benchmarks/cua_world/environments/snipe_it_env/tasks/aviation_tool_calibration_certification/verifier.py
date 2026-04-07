#!/usr/bin/env python3
"""Verifier for aviation_tool_calibration_certification task.

Scoring breakdown (100 points):
  C1: PDF files uploaded to all 4 target assets (15 pts)
  C2: PDF certificates accurately matched to correct assets (25 pts)
  C3: Status updated to 'Ready to Deploy' (20 pts)
  C4: Next Calibration Date updated to '2027-03-01' (15 pts)
  C5: Notes updated with 'Calibrated by Midwest Metrology' (15 pts)
  C6: Decoys (ASSET-CAL-005, 006) strictly left untouched (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)
RESULT_PATH = "/tmp/calibration_result.json"


def verify_calibration_certification(traj, env_info, task_info):
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

    targets = ["ASSET-CAL-001", "ASSET-CAL-002", "ASSET-CAL-003", "ASSET-CAL-004"]
    decoys = ["ASSET-CAL-005", "ASSET-CAL-006"]
    assets_by_tag = {a["tag"]: a for a in result.get("assets", [])}

    # --- Anti-Gaming / Do-Nothing Check ---
    any_modified = False
    for tag in targets:
        asset = assets_by_tag.get(tag, {})
        if (asset.get("uploaded_files") or 
            asset.get("status") == "Ready to Deploy" or 
            asset.get("cal_date") == "2027-03-01" or 
            "Calibrated by Midwest Metrology" in asset.get("notes", "")):
            any_modified = True
            break
            
    if not any_modified:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No target assets were updated."}

    # --- C1 & C2: File Uploads & Matching (15 + 25 pts) ---
    files_uploaded = 0
    files_matched = 0
    
    for tag in targets:
        asset = assets_by_tag.get(tag, {})
        uploads = asset.get("uploaded_files", "")
        if uploads:
            files_uploaded += 1
            # Check for correct certificate filename matching the asset
            expected_filename = f"Cert_CAL-{tag[-3:]}"
            if expected_filename.lower() in uploads.lower():
                files_matched += 1
            else:
                feedback.append(f"C2 Error: {tag} has upload but does not match expected {expected_filename}.")

    c1_score = int((files_uploaded / 4) * 15)
    score += c1_score
    feedback.append(f"C1: {files_uploaded}/4 files uploaded (+{c1_score})")

    c2_score = int((files_matched / 4) * 25)
    score += c2_score
    feedback.append(f"C2: {files_matched}/4 certificates accurately matched to correct assets (+{c2_score})")

    # --- C3: Status Updated (20 pts) ---
    status_updated = 0
    for tag in targets:
        asset = assets_by_tag.get(tag, {})
        if asset.get("status") == "Ready to Deploy":
            status_updated += 1
    
    c3_score = int((status_updated / 4) * 20)
    score += c3_score
    feedback.append(f"C3: {status_updated}/4 statuses updated to 'Ready to Deploy' (+{c3_score})")

    # --- C4: Next Calibration Date (15 pts) ---
    date_updated = 0
    for tag in targets:
        asset = assets_by_tag.get(tag, {})
        if asset.get("cal_date") == "2027-03-01":
            date_updated += 1
            
    c4_score = int((date_updated / 4) * 15)
    score += c4_score
    feedback.append(f"C4: {date_updated}/4 calibration dates updated (+{c4_score})")

    # --- C5: Notes (15 pts) ---
    notes_updated = 0
    for tag in targets:
        asset = assets_by_tag.get(tag, {})
        if "Calibrated by Midwest Metrology" in asset.get("notes", ""):
            notes_updated += 1
            
    c5_score = int((notes_updated / 4) * 15)
    score += c5_score
    feedback.append(f"C5: {notes_updated}/4 notes properly updated (+{c5_score})")

    # --- C6: Decoys untouched (10 pts) ---
    decoys_untouched = 0
    for tag in decoys:
        asset = assets_by_tag.get(tag, {})
        is_touched = False
        
        if asset.get("uploaded_files"):
            is_touched = True
            feedback.append(f"C6 Error: Decoy {tag} had a file uploaded.")
        if asset.get("status") != "Ready to Deploy":
            is_touched = True
            feedback.append(f"C6 Error: Decoy {tag} status was changed.")
        if asset.get("cal_date") == "2027-03-01":
            is_touched = True
            feedback.append(f"C6 Error: Decoy {tag} date was changed.")
        if "Midwest Metrology" in asset.get("notes", ""):
            is_touched = True
            feedback.append(f"C6 Error: Decoy {tag} notes were changed.")
            
        if not is_touched:
            decoys_untouched += 1

    c6_score = int((decoys_untouched / 2) * 10)
    score += c6_score
    feedback.append(f"C6: {decoys_untouched}/2 decoys left completely unmodified (+{c6_score})")

    # Passing logic: must score at least 70 AND correctly match at least some certificates to prevent bulk editing hacks
    passed = score >= 70 and files_matched > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }