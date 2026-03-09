#!/usr/bin/env python3
"""
Verifier for government_rfp_compliance task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rfp_compliance(traj, env_info, task_info):
    """
    Verify that the proposal document exists and meets strict formatting requirements.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_heading_count = 4 # Executive Summary, Technical Approach, Implementation Plan, Past Performance

    # 1. Get result JSON
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

    # 2. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: File Exists (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: Margins Correct (30 pts)
    # This is the hardest part - user must adjust Page Style
    if result.get("margins_correct"):
        score += 30
        feedback.append("Page margins compliant (1 inch).")
    else:
        margins = result.get("margins_details", {})
        feedback.append(f"Margins incorrect. Found: {margins}")

    # Criterion 3: Header Correct (20 pts)
    if result.get("header_text_found"):
        score += 20
        feedback.append("Header text correct.")
    else:
        feedback.append("Header text missing or incorrect.")

    # Criterion 4: Footer Page Number (10 pts)
    if result.get("footer_page_number_found"):
        score += 10
        feedback.append("Footer page numbers present.")
    else:
        feedback.append("Footer page numbers missing.")

    # Criterion 5: Heading Styles (20 pts)
    # We expect 4 sections with Heading 1
    h1_count = result.get("heading1_count", 0)
    if h1_count >= expected_heading_count:
        score += 20
        feedback.append(f"Heading styles applied correctly ({h1_count} sections).")
    elif h1_count > 0:
        score += 10
        feedback.append(f"Partial heading styles ({h1_count}/{expected_heading_count}).")
    else:
        feedback.append("No 'Heading 1' styles found.")

    # Criterion 6: Content Present (10 pts)
    if result.get("content_found"):
        score += 10
        feedback.append("Document content verified.")
    else:
        feedback.append("Document appears empty or missing key text.")

    # 3. Final Determination
    # Threshold 70.
    # Must have File (10) + Margins (30) + Header (20) + Content (10) = 70 to pass reasonably.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }