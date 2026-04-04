#!/usr/bin/env python3
"""
Verifier for teacher_salary_schedule task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_salary_schedule(traj, env_info, task_info):
    """
    Verify the created salary schedule document.
    
    Criteria:
    1. File exists and was created during task (Gatekeeper)
    2. Document Structure (Headings, Tables, TOC, Footer)
    3. Data Accuracy (Spot check specific salary numbers)
    """
    
    # 1. Setup: Get result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Gatekeeper Checks
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file 'Maplewood_Salary_Schedule_2024_2025.odt' was not found."}
    
    if result.get("file_size", 0) < 5000:
        return {"passed": False, "score": 5, "feedback": "File exists but is too small (<5KB). Likely empty or missing substantial content."}

    # 3. Scoring
    score = 0
    feedback = []
    
    # Base points for valid file
    score += 5
    feedback.append("File created successfully (+5)")

    # Structure Scoring (Max 65 pts)
    # Headings
    h1 = result.get("heading1_count", 0)
    h2 = result.get("heading2_count", 0)
    if h1 >= 4:
        score += 12
        feedback.append(f"Heading 1 sections present ({h1}) (+12)")
    elif h1 > 0:
        score += 5
        feedback.append(f"Heading 1 sections partial ({h1}/4) (+5)")
    else:
        feedback.append("Missing Heading 1 sections")

    if h2 >= 4:
        score += 8
        feedback.append(f"Heading 2 subsections present ({h2}) (+8)")
    elif h2 > 0:
        score += 3
        feedback.append(f"Heading 2 subsections partial ({h2}/4) (+3)")
    else:
        feedback.append("Missing Heading 2 subsections")

    # Tables
    tables = result.get("table_count", 0)
    if tables >= 3:
        score += 20
        feedback.append(f"All required tables present ({tables}) (+20)")
    elif tables >= 1:
        score += 10
        feedback.append(f"Some tables present ({tables}/3) (+10)")
    else:
        feedback.append("No tables found")

    # TOC
    if result.get("has_toc"):
        score += 15
        feedback.append("Table of Contents found (+15)")
    else:
        feedback.append("Table of Contents missing")

    # Footer/Page Numbers
    if result.get("has_page_numbers"):
        score += 10
        feedback.append("Page numbers found (+10)")
    else:
        feedback.append("Page numbers missing")

    # Content Scoring (Max 30 pts)
    # Check 5 specific values
    checks = result.get("content_checks", {})
    content_score = 0
    
    if checks.get("val_42500"): content_score += 5
    if checks.get("val_72835"): content_score += 5
    if checks.get("val_84750"): content_score += 5
    if checks.get("val_6200"):  content_score += 5
    if checks.get("district_name"): content_score += 5
    
    score += content_score
    feedback.append(f"Data accuracy check: {content_score}/25 points")
    
    # Length check (Max 5 pts)
    if result.get("paragraph_count", 0) >= 20:
        score += 5
    else:
        feedback.append("Document appears too short")

    # 4. Final Determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }