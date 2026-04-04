#!/usr/bin/env python3
"""
Verifier for agronomy_scouting_report task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_agronomy_report(traj, env_info, task_info):
    """
    Verifies the agronomy scouting report creation task.
    
    Criteria:
    1. Output file exists and was created during the task. (10 pts)
    2. Header contains 'AgriScan' and Footer contains page numbers. (15 pts)
    3. Proper Heading 1 styles used for sections (Field Info, Observations, Recs). (15 pts)
    4. Table present for observations. (25 pts)
    5. Correct data included (Potato Leafhopper, Warrior II). (15 pts)
    6. Safety critical: REI value "24 hours" is bolded. (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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

    score = 0
    feedback = []
    
    # 1. File Existence and Validity (10 pts)
    if result.get("file_exists") and result.get("created_during_task"):
        score += 10
        feedback.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file missing or not created during task."}

    analysis = result.get("odt_analysis", {})
    content_check = analysis.get("content_check", {})

    # 2. Header/Footer (15 pts)
    if analysis.get("has_header"):
        score += 10
        feedback.append("Header present.")
    else:
        feedback.append("Missing 'AgriScan' header.")
        
    if analysis.get("has_footer"):
        score += 5
        feedback.append("Footer/Page numbers present.")
    else:
        feedback.append("Missing footer/page numbers.")

    # 3. Heading Styles (15 pts)
    h1_count = analysis.get("heading1_count", 0)
    if h1_count >= 3:
        score += 15
        feedback.append(f"Correct heading styles usage ({h1_count} sections).")
    elif h1_count > 0:
        score += 5
        feedback.append(f"Partial heading styles usage ({h1_count} found, expected 3+).")
    else:
        feedback.append("No Heading 1 styles detected.")

    # 4. Table (25 pts)
    if analysis.get("has_table"):
        score += 25
        feedback.append("Observation table present.")
    else:
        feedback.append("Missing observation table.")

    # 5. Data Accuracy (15 pts)
    data_score = 0
    if content_check.get("pest_name"): data_score += 5
    if content_check.get("chemical_name"): data_score += 5
    if content_check.get("rei_text"): data_score += 5
    score += data_score
    if data_score == 15:
        feedback.append("All key data points found.")
    else:
        feedback.append("Some data points missing (Pest/Chemical/REI).")

    # 6. Safety Compliance - Bold REI (20 pts)
    if analysis.get("rei_bold_check"):
        score += 20
        feedback.append("Safety compliance: REI is bolded.")
    else:
        feedback.append("Safety violation: REI '24 hours' is NOT bolded.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }