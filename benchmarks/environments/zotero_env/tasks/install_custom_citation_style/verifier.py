#!/usr/bin/env python3
"""
Verifier for install_custom_citation_style task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_custom_citation_style(traj, env_info, task_info):
    """
    Verify that the custom citation style was installed and used to generate a bibliography.
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

    # Extract metrics
    output_exists = result.get("output_exists", False)
    marker_found = result.get("marker_found", False)
    authors_found_count = result.get("authors_found_count", 0)
    style_installed = result.get("style_installed", False)
    file_created_during_task = result.get("file_created_during_task", False)
    
    score = 0
    feedback_parts = []

    # Criterion 1: Bibliography file created (20 pts)
    # Must be created during task to count
    if output_exists and file_created_during_task:
        score += 20
        feedback_parts.append("Bibliography file created successfully")
    elif output_exists:
        # File exists but old? Suspicious.
        score += 5
        feedback_parts.append("Bibliography file exists but timestamp is old")
    else:
        feedback_parts.append("Bibliography file not found")

    # Criterion 2: Style Installed (20 pts)
    if style_installed:
        score += 20
        feedback_parts.append("Custom style installed in Zotero profile")
    else:
        feedback_parts.append("Custom style not found in Zotero profile")

    # Criterion 3: Correct Style Used (30 pts)
    # Checked via unique marker [JAA]
    if marker_found:
        score += 30
        feedback_parts.append("Correct custom style used (marker [JAA] found)")
    else:
        if output_exists:
            feedback_parts.append("Wrong style used (marker [JAA] missing)")
        
    # Criterion 4: Correct Content (30 pts, 10 per author)
    if authors_found_count == 3:
        score += 30
        feedback_parts.append("All 3 target papers found in bibliography")
    elif authors_found_count > 0:
        partial = authors_found_count * 10
        score += partial
        feedback_parts.append(f"Partial content: {authors_found_count}/3 papers found")
    else:
        if output_exists:
            feedback_parts.append("No target papers found in bibliography")

    # Pass threshold
    passed = (score >= 70) and marker_found and output_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }