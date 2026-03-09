#!/usr/bin/env python3
"""
Verifier for upload_and_process_incident_report task.

Checks:
1. Document "Incident_Report.txt" is uploaded to the case.
2. Case "incidentDate" matches the ground truth.
3. A Case Note exists containing the Officer Name.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upload_and_process_incident_report(traj, env_info, task_info):
    """
    Verify the ArkCase task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Ground Truth and Result from Env
    ground_truth = {}
    result = {}
    
    # Create temp files
    gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    res_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    
    try:
        # Copy files
        copy_from_env("/tmp/ground_truth.json", gt_temp)
        copy_from_env("/tmp/task_result.json", res_temp)
        
        # Load JSON
        with open(gt_temp, 'r') as f:
            ground_truth = json.load(f)
        with open(res_temp, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(gt_temp): os.unlink(gt_temp)
        if os.path.exists(res_temp): os.unlink(res_temp)

    # Extract Ground Truth
    expected_date = ground_truth.get("date", "YYYY-MM-DD")
    expected_officer = ground_truth.get("officer", "Officer Name")
    
    score = 0
    feedback = []
    
    # 2. Check Document Upload (30 pts)
    # The 'case_docs' might be a list of objects or a dict with 'results'
    docs_data = result.get("case_docs", [])
    if isinstance(docs_data, dict):
        docs_data = docs_data.get("results", []) or docs_data.get("list", []) or []
        
    # Look for filename
    doc_uploaded = False
    for doc in docs_data:
        # Check various common name fields
        name = doc.get("name", "") or doc.get("title", "") or doc.get("objectName", "")
        if "Incident_Report.txt" in name:
            doc_uploaded = True
            break
            
    if doc_uploaded:
        score += 30
        feedback.append("Document 'Incident_Report.txt' uploaded successfully.")
    else:
        feedback.append("Document 'Incident_Report.txt' NOT found in case documents.")

    # 3. Check Incident Date (40 pts)
    case_details = result.get("case_details", {})
    actual_date = case_details.get("incidentDate", "")
    case_desc = case_details.get("details", "") or ""
    
    date_correct = False
    if expected_date in str(actual_date):
        score += 40
        date_correct = True
        feedback.append(f"Incident Date updated correctly to {expected_date}.")
    elif expected_date in case_desc:
        # Partial credit if they put it in the description because they couldn't find the field
        score += 20
        feedback.append(f"Incident Date found in description, but field not updated (Partial Credit).")
    else:
        feedback.append(f"Incident Date incorrect. Expected {expected_date}, got '{actual_date}'.")

    # 4. Check Officer Note (30 pts)
    notes_data = result.get("case_notes", [])
    if isinstance(notes_data, dict):
        notes_data = notes_data.get("results", []) or []
        
    note_found = False
    for note in notes_data:
        text = note.get("text", "") or note.get("content", "") or note.get("noteText", "")
        if expected_officer.lower() in text.lower():
            note_found = True
            break
            
    if note_found:
        score += 30
        feedback.append(f"Case note found referencing '{expected_officer}'.")
    else:
        feedback.append(f"No case note found containing officer name '{expected_officer}'.")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }