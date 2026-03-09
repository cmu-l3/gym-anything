#!/usr/bin/env python3
"""
Verifier for atlas_map_generation_brazil task.

Checks:
1. PDF output exists and has content (20 pts)
2. QGIS Project file exists (10 pts)
3. Internal Project XML Analysis:
   - Print Layout exists (10 pts)
   - Atlas is enabled (25 pts)
   - Coverage layer is set (15 pts)
   - Map item is controlled by Atlas (10 pts)
   - Filter expression correctly selects Brazil (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_atlas_map_generation_brazil(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    logger.info(f"Task result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}
    
    # 1. PDF Check (20 pts)
    if result.get('pdf_exists', False):
        size = result.get('pdf_size_bytes', 0)
        if size > 1000: # Reasonable PDF size
            score += 20
            subscores['pdf'] = True
            feedback_parts.append("Valid PDF output found")
        else:
            score += 5
            subscores['pdf'] = False
            feedback_parts.append("PDF exists but is suspicious (too small)")
    else:
        subscores['pdf'] = False
        feedback_parts.append("PDF output NOT found")

    # 2. Project File Check (10 pts)
    if result.get('project_exists', False):
        score += 10
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file NOT found")

    # 3. Atlas Configuration Analysis
    analysis = result.get('atlas_analysis', {})
    
    # Layout Exists (10 pts)
    if analysis.get('has_layout', False):
        score += 10
        feedback_parts.append("Print Layout created")
    else:
        feedback_parts.append("No Print Layout found in project")

    # Atlas Enabled (25 pts)
    if analysis.get('atlas_enabled', False):
        score += 25
        subscores['atlas_enabled'] = True
        feedback_parts.append("Atlas is enabled")
    else:
        subscores['atlas_enabled'] = False
        feedback_parts.append("Atlas NOT enabled")

    # Coverage Layer Set (15 pts)
    if analysis.get('coverage_layer_set', False):
        score += 15
        feedback_parts.append("Coverage layer configured")
    else:
        feedback_parts.append("Coverage layer NOT set")

    # Filter Correct (10 pts)
    if analysis.get('filter_on', False):
        if analysis.get('filter_brazil', False):
            score += 10
            feedback_parts.append("Filter correctly set for Brazil")
        else:
            score += 5
            feedback_parts.append("Filter active but 'Brazil' not detected in expression")
    else:
        feedback_parts.append("Filter features NOT enabled")

    # Controlled by Atlas (10 pts)
    if analysis.get('controlled_by_atlas', False):
        score += 10
        feedback_parts.append("Map item controlled by Atlas")
    else:
        feedback_parts.append("Map item NOT controlled by Atlas (won't zoom to feature)")

    # Pass logic: Must have PDF + Atlas Enabled + Score >= 65
    passed = (score >= 65) and subscores.get('pdf', False) and subscores.get('atlas_enabled', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }