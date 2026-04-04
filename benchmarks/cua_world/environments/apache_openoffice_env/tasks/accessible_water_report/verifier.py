#!/usr/bin/env python3
"""
Verifier for accessible_water_report task.
Verifies Section 508 accessibility features in an ODT document.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_accessible_water_report(traj, env_info, task_info):
    """
    Verify the Water Quality Report ODT file for accessibility compliance.
    
    Criteria:
    1. File exists and created during task.
    2. Uses Semantic Headings (Outline Level 1 & 2).
    3. Image inserted with correct Alt Text (svg:desc).
    4. Table has Header Rows defined (table:table-header-rows).
    5. Document Title metadata set.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
    
    # Copy the analysis JSON from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Critical Gate: File must exist
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Task Failed: Output file 'Oakwood_CCR_2024.odt' was not created."}
        
    score += 10
    feedback.append("File created successfully.")
    
    # Styles (30 pts)
    if result.get("has_heading1"):
        score += 15
        feedback.append("Heading 1 style applied correctly.")
    else:
        feedback.append("Missing Heading 1 style (Structure).")
        
    if result.get("has_heading2"):
        score += 15
        feedback.append("Heading 2 style applied correctly.")
    else:
        feedback.append("Missing Heading 2 style (Structure).")
        
    # Image & Alt Text (30 pts)
    if result.get("has_image"):
        score += 10
        feedback.append("Chart image inserted.")
        
        if result.get("alt_text_correct"):
            score += 20
            feedback.append("Image Alt Text is correct.")
        else:
            found = result.get("alt_text_found", "None")
            feedback.append(f"Incorrect Alt Text. Expected stability description, found: '{found}'.")
    else:
        feedback.append("Chart image missing.")
        
    # Table & Headers (25 pts)
    if result.get("has_table"):
        score += 5
        feedback.append("Table created.")
        
        if result.get("has_header_row"):
            score += 20
            feedback.append("Table Header Row configured correctly.")
        else:
            feedback.append("Table Header Row NOT configured (Accessibility violation).")
    else:
        feedback.append("Table missing.")
        
    # Metadata (5 pts)
    if result.get("title_metadata_correct"):
        score += 5
        feedback.append("Document Title property set.")
    else:
        feedback.append("Document Title property missing or incorrect.")
        
    # 3. Final Result
    # Pass threshold 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }