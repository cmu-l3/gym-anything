#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_blind_resume(traj, env_info, task_info):
    """
    Verifies the blind resume reformat task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON
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

    # Scoring
    score = 0
    feedback = []
    
    # 1. File Exists (10 pts)
    if result.get("file_exists", False):
        score += 10
        feedback.append("File created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Anonymization (30 pts) - CRITICAL
    pii_found = result.get("pii_found", [])
    if not pii_found:
        score += 30
        feedback.append("Anonymization successful (no PII found).")
    else:
        feedback.append(f"Anonymization FAILED. Found PII: {', '.join(pii_found)}.")

    # 3. Identification (10 pts)
    if result.get("id_found", False):
        score += 10
        feedback.append("Candidate ID present.")
    else:
        feedback.append("Candidate ID missing.")

    # 4. Heading Styles (20 pts)
    h1 = result.get("heading1_count", 0)
    h2 = result.get("heading2_count", 0)
    if h1 >= 3: # Expecting 4 sections
        score += 10
        feedback.append(f"Heading 1 styles applied ({h1}).")
    else:
        feedback.append(f"Heading 1 styles missing or insufficient ({h1}).")
        
    if h2 >= 2: # Expecting 3 jobs
        score += 10
        feedback.append(f"Heading 2 styles applied ({h2}).")
    else:
        feedback.append(f"Heading 2 styles missing or insufficient ({h2}).")

    # 5. Skills Table (15 pts)
    if result.get("table_found", False):
        score += 15
        feedback.append("Skills converted to Table.")
    else:
        feedback.append("Skills list NOT converted to Table.")

    # 6. Footer (15 pts)
    if result.get("footer_found", False):
        score += 15
        feedback.append("Footer present.")
    else:
        feedback.append("Footer missing.")

    # Pass Threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }