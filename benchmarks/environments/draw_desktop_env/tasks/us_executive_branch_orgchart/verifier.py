#!/usr/bin/env python3
"""
Verifier for us_executive_branch_orgchart task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_us_executive_branch_orgchart(traj, env_info, task_info):
    """Verify US Executive Branch Org Chart creation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    required_depts = metadata.get('required_departments', [])
    min_depts = metadata.get('min_departments', 12)
    min_agencies = metadata.get('min_agencies', 4)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File saved and modified (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Draw.io file saved")
    else:
        feedback.append("FAIL: Draw.io file not saved or not modified")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    analysis = result.get('analysis', {})
    
    # 2. Departments found (25 pts)
    depts_found = len(analysis.get('departments_found', []))
    if depts_found >= min_depts:
        score += 25
        feedback.append(f"Departments: {depts_found}/15 (Good)")
    elif depts_found >= 5:
        score += 10
        feedback.append(f"Departments: {depts_found}/15 (Partial)")
    else:
        feedback.append(f"Departments: {depts_found}/15 (Fail)")

    # 3. Officers (President/VP) (10 pts)
    officers_found = len(analysis.get('officers_found', []))
    if officers_found >= 1: # At least one
        score += 10
        feedback.append("Officers found")
    else:
        feedback.append("Missing President/VP")

    # 4. Hierarchical Connections (10 pts)
    num_edges = analysis.get('num_edges', 0)
    if num_edges >= 8:
        score += 10
        feedback.append(f"Connections: {num_edges}")
    elif num_edges >= 4:
        score += 5
        feedback.append(f"Connections: {num_edges} (partial)")
    else:
        feedback.append("Missing connections")

    # 5. Colors (10 pts)
    colors = analysis.get('distinct_colors', 0)
    if colors >= 3:
        score += 10
        feedback.append(f"Colors: {colors}")
    elif colors >= 2:
        score += 5
        feedback.append(f"Colors: {colors} (partial)")
    else:
        feedback.append("Monochrome/Default colors used")

    # 6. Establishment Years (10 pts)
    years = analysis.get('years_found', 0)
    if years >= 8:
        score += 10
        feedback.append(f"Years: {years}")
    elif years >= 4:
        score += 5
        feedback.append(f"Years: {years} (partial)")
    else:
        feedback.append("Missing establishment years")

    # 7. Pages (10 pts)
    pages = analysis.get('num_pages', 0)
    if pages >= 2:
        score += 10
        feedback.append("Multiple pages created")
    else:
        feedback.append("Single page only")

    # 8. Agencies (Page 2) (5 pts)
    agencies = len(analysis.get('agencies_found', []))
    if agencies >= min_agencies:
        score += 5
        feedback.append(f"Agencies: {agencies}")
    elif agencies >= 2:
        score += 3
        feedback.append(f"Agencies: {agencies} (partial)")
    
    # 9. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 2000:
        score += 10
        feedback.append("PNG export valid")
    else:
        feedback.append("PNG export missing or empty")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }