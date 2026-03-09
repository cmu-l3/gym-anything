#!/usr/bin/env python3
"""
Verifier for transcribe_paper_complaint task.
Checks if the agent correctly transcribed a PDF form into ArkCase.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transcribe_paper_complaint(traj, env_info, task_info):
    """
    Verifies that the complaint was created with correct details.
    
    Scoring:
    - Complaint Created: 20 pts
    - Correct Complainant (Eleanor Rigby): 30 pts
    - Correct Date (2025-02-14): 15 pts
    - Title Accuracy (Keywords): 15 pts
    - Description Accuracy (Keywords): 20 pts
    
    Pass threshold: 85 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title_keywords = metadata.get('expected_title_keywords', ["Construction", "Noise"])
    expected_date = metadata.get('expected_date', "2025-02-14")
    expected_desc_keywords = metadata.get('expected_description_keywords', ["funeral", "jackhammer"])
    
    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 2. Check: Complaint Found
    if not result.get('complaint_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new complaint found in ArkCase. Did you save the case?"
        }
    
    score += 20
    feedback.append("Complaint case created.")
    
    # 3. Check: Complainant/Requestor
    # We accept ID match or Name match (in case ID is not cleanly exposed in summary API)
    req_name = result.get('requestor_name', '').lower()
    
    # We know the expected name is Eleanor Rigby
    if "eleanor" in req_name and "rigby" in req_name:
        score += 30
        feedback.append("Complainant correctly linked to Eleanor Rigby.")
    else:
        feedback.append(f"Incorrect complainant. Expected 'Eleanor Rigby', got '{result.get('requestor_name', 'Unknown')}'.")

    # 4. Check: Date
    # Date formats can vary (2025-02-14T00:00:00Z etc). We look for the date string.
    inc_date = result.get('incident_date', '')
    if expected_date in inc_date:
        score += 15
        feedback.append("Incident date is correct.")
    else:
        feedback.append(f"Incident date mismatch. Expected '{expected_date}', got '{inc_date}'.")
        
    # 5. Check: Title
    title = result.get('title', '')
    title_matches = sum(1 for kw in expected_title_keywords if kw.lower() in title.lower())
    if title_matches >= 2:
        score += 15
        feedback.append("Title contains correct keywords.")
    elif title_matches == 1:
        score += 7
        feedback.append("Title partially correct.")
    else:
        feedback.append(f"Title incorrect. Got: '{title}'")
        
    # 6. Check: Description
    desc = result.get('description', '')
    desc_matches = sum(1 for kw in expected_desc_keywords if kw.lower() in desc.lower())
    # We expect at least 2 keywords for full points
    if desc_matches >= 2:
        score += 20
        feedback.append("Description transcribed accurately.")
    elif desc_matches == 1:
        score += 10
        feedback.append("Description missing some details.")
    else:
        feedback.append("Description missing or inaccurate.")

    # Final Evaluation
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }