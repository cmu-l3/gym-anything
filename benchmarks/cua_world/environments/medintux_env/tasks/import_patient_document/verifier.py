#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_patient_document(traj, env_info, task_info):
    """
    Verify the import_patient_document task.
    
    Expected outcomes:
    1. A document record exists for patient Jean DUPONT in RubriquesHead.
    2. The document label is "Compte Rendu Cardio".
    3. The document contains data (blob size > 0).
    4. The document date is today.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_label = metadata.get('expected_label', 'Compte Rendu Cardio').lower()
    
    score = 0
    feedback = []
    
    # 1. Patient Selection / Record Creation (Max 50)
    if result.get("document_found", False):
        score += 50
        feedback.append("Document record created in patient file.")
        
        # 2. Label Verification (Max 20)
        actual_label = result.get("document_label", "").strip()
        if expected_label in actual_label.lower():
            score += 20
            feedback.append(f"Label correct ('{actual_label}').")
        else:
            feedback.append(f"Label incorrect. Expected containing '{expected_label}', got '{actual_label}'.")
            
        # 3. Content Verification (Max 20)
        blob_size = int(result.get("document_blob_size", 0))
        if blob_size > 100: # Arbitrary small threshold for a PDF
            score += 20
            feedback.append(f"Document content stored ({blob_size} bytes).")
        else:
            feedback.append(f"Document appears empty or corrupted (Size: {blob_size}).")
            
        # 4. Date Verification (Max 10)
        expected_date = result.get("expected_date", "")
        actual_date = result.get("document_date", "").split(" ")[0] # Handle datetime if needed
        if expected_date and actual_date == expected_date:
            score += 10
            feedback.append(f"Date is correct ({actual_date}).")
        else:
            feedback.append(f"Date incorrect. Expected {expected_date}, got {actual_date}.")
            
    else:
        feedback.append("No document record found for patient Jean DUPONT.")
        # Check if they at least opened the app
        if result.get("app_running", False):
            score += 5
            feedback.append("Application was running.")

    # VLM Verification (Bonus/Confirmation)
    # If we have a trajectory, we could check if the file picker was opened
    # For now, we rely on the strong database evidence
    
    passed = score >= 70 and result.get("document_found", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }