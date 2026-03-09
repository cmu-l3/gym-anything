#!/usr/bin/env python3
"""
Verifier for org_chart_corporate_restructure@1.
Checks if the organizational chart was updated correctly based on the JSON analysis from the container.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_org_chart_corporate_restructure(traj, env_info, task_info):
    """
    Verify the organizational chart updates.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Criteria
    score = 0
    feedback_parts = []
    
    # Metadata requirements
    metadata = task_info.get('metadata', {})
    req_labels_present = metadata.get('required_labels_present', [])
    req_labels_absent = metadata.get('required_labels_absent', [])
    min_shapes = metadata.get('min_shapes', 17)
    
    all_text = result.get("all_text", "").lower()

    # 1. File Modification (5 pts)
    if result.get("file_modified"):
        score += 5
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified")

    # 2. Key Personnel & Titles (50 pts total)
    # Check for presence of required strings (case insensitive search in accumulated text)
    found_count = 0
    missing_items = []
    
    # We group strict pairs (Title + Name) generally, but for loose verification we check if tokens exist.
    # The list in metadata is flat. We iterate it.
    for label in req_labels_present:
        if label.lower() in all_text:
            found_count += 1
        else:
            missing_items.append(label)
    
    # Calculate score for labels found
    # Total labels to find = len(req_labels_present)
    total_req = len(req_labels_present)
    if total_req > 0:
        label_score = (found_count / total_req) * 50
        score += label_score
        feedback_parts.append(f"Labels found: {found_count}/{total_req}")
        if missing_items:
            feedback_parts.append(f"Missing: {', '.join(missing_items[:3])}...")

    # 3. Removed Roles (10 pts)
    # Check that old titles/names are NOT present
    clean_removals = 0
    for label in req_labels_absent:
        if label.lower() not in all_text:
            clean_removals += 1
        else:
            feedback_parts.append(f"Failed to remove: {label}")
            
    if len(req_labels_absent) > 0:
        removal_score = (clean_removals / len(req_labels_absent)) * 10
        score += removal_score

    # 4. Structural Integrity (15 pts)
    # Expect roughly 17 nodes (people boxes)
    node_count = result.get("node_count", 0)
    if node_count >= 17:
        score += 15
        feedback_parts.append(f"Structure intact ({node_count} nodes)")
    elif node_count >= 15:
        score += 10
        feedback_parts.append(f"Structure mostly intact ({node_count} nodes)")
    else:
        feedback_parts.append(f"Structure count low ({node_count}/17)")

    # 5. Color Coding (10 pts)
    # Expect at least 4 distinct non-white colors
    distinct_colors = result.get("distinct_colors", 0)
    if distinct_colors >= 4:
        score += 10
        feedback_parts.append(f"Color coding applied ({distinct_colors} colors)")
    elif distinct_colors >= 2:
        score += 5
        feedback_parts.append("Partial color coding")
    else:
        feedback_parts.append("Color coding missing")

    # 6. Exports (10 pts)
    if result.get("png_exists") and result.get("png_size", 0) > 1000:
        score += 5
        feedback_parts.append("PNG exported")
    
    if result.get("pdf_exists") and result.get("pdf_size", 0) > 1000:
        score += 5
        feedback_parts.append("PDF exported")

    # Final Score Rounding
    score = round(score)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }