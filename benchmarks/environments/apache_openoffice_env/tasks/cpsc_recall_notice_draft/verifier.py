#!/usr/bin/env python3
"""
Verifier for cpsc_recall_notice_draft task.
Checks if the agent created a CPSC-compliant ODT file with correct structure and data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cpsc_recall_draft(traj, env_info, task_info):
    """
    Verify the recall draft document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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

    # Basic File Checks
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Recall draft document was not saved to /home/ga/Documents/Steamfast_Recall_Draft.odt"
        }

    if not result.get("created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Document timestamp indicates it was not created during the task session."
        }
        
    analysis = result.get("analysis", {})
    score = 0
    feedback = []

    # 1. File Created (10 pts)
    score += 10
    feedback.append("File created successfully.")

    # 2. Header Check (10 pts)
    if analysis.get("has_release_header"):
        score += 10
        feedback.append("Found 'FOR IMMEDIATE RELEASE' header.")
    else:
        feedback.append("Missing 'FOR IMMEDIATE RELEASE' header.")

    # 3. Structure: Heading Styles (20 pts)
    # We expect at least 1 Heading 1 (Headline) and at least 4 Heading 2s (Sections)
    h1_count = analysis.get("heading1_count", 0)
    h2_count = analysis.get("heading2_count", 0)
    
    if h1_count >= 1:
        score += 5
        feedback.append("Headline uses Heading 1 style.")
    else:
        feedback.append("Headline does not use Heading 1 style.")
        
    if h2_count >= 4:
        score += 15
        feedback.append(f"Found {h2_count} section headings using Heading 2 style.")
    elif h2_count > 0:
        score += 5
        feedback.append(f"Found only {h2_count} Heading 2 sections (expected >= 4).")
    else:
        feedback.append("No Heading 2 styles found for sections.")

    # 4. Table Check (20 pts)
    if analysis.get("table_count", 0) >= 1:
        score += 20
        feedback.append("Found a table for model numbers.")
    else:
        feedback.append("No table found in document.")

    # 5. Content Data Integrity (25 pts)
    # Phone number (5 pts)
    if analysis.get("has_phone"):
        score += 5
    else:
        feedback.append("Correct phone number (866-827-3362) not found.")
        
    # Hazard text (5 pts)
    if analysis.get("has_hazard_text"):
        score += 5
    else:
        feedback.append("Specific hazard description (cord bushing/burn) not found.")
        
    # Model numbers (15 pts) - Prorated
    # There are 10 models. 1.5 pts per model.
    model_count = analysis.get("model_count", 0)
    model_score = min(15, int(model_count * 1.5))
    score += model_score
    if model_count < 10:
        feedback.append(f"Only found {model_count}/10 model numbers.")
    else:
        feedback.append("All model numbers present.")

    # 6. Footer Marker (15 pts)
    if analysis.get("has_footer_marker"):
        score += 15
        feedback.append("Found end-of-release marker '###'.")
    else:
        feedback.append("Missing end-of-release marker '###'.")

    # Final Verdict
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }