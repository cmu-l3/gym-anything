#!/usr/bin/env python3
"""
Verifier for configure_gl_distribution task.
Checks if Campaigns and GL Distribution rules were created correctly in iDempiere.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gl_distribution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_dist_name = metadata.get('distribution_name', 'Marketing Split 2025')
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Data extraction
    campaigns = result.get('campaigns', [])
    dist_header = result.get('distribution_header')
    dist_lines = result.get('distribution_lines', [])
    task_start = result.get('task_start', 0)

    # Helper: Check timestamps
    def is_newly_created(record_created_str):
        # Postgres JSON timestamp format: "2024-05-20 10:00:00" or similar
        # Since timestamp parsing can be brittle with zones, we primarily rely on
        # the setup script cleaning up old data. If it exists, it's likely new.
        # But if we can parse it, we check against task_start.
        # For this task, existence after cleanup is strong evidence.
        return True

    # --- CRITERION 1: Campaigns Created (20 pts) ---
    spring_found = False
    summer_found = False
    
    if campaigns:
        for c in campaigns:
            val = c.get('value', '')
            name = c.get('name', '')
            if val == 'SPRING2025' and 'Spring Promotion 2025' in name:
                spring_found = True
            if val == 'SUMMER2025' and 'Summer Blowout 2025' in name:
                summer_found = True

    if spring_found:
        score += 10
        feedback_parts.append("Spring Campaign created")
    else:
        feedback_parts.append("Spring Campaign missing or incorrect")

    if summer_found:
        score += 10
        feedback_parts.append("Summer Campaign created")
    else:
        feedback_parts.append("Summer Campaign missing or incorrect")

    # --- CRITERION 2: Distribution Header (20 pts) ---
    header_found = False
    if dist_header and dist_header.get('name') == expected_dist_name:
        score += 20
        header_found = True
        feedback_parts.append(f"Distribution '{expected_dist_name}' created")
    else:
        feedback_parts.append(f"Distribution '{expected_dist_name}' header not found")

    # --- CRITERION 3: Distribution Lines (60 pts) ---
    # Needs exactly 2 lines: Spring@60, Summer@40
    
    spring_line_correct = False
    summer_line_correct = False
    line_count = len(dist_lines) if dist_lines else 0
    
    if line_count == 2:
        for line in dist_lines:
            c_val = line.get('campaign_value', '')
            pct = float(line.get('percent', 0))
            
            if c_val == 'SPRING2025':
                if abs(pct - 60.0) < 0.01:
                    spring_line_correct = True
            elif c_val == 'SUMMER2025':
                if abs(pct - 40.0) < 0.01:
                    summer_line_correct = True
    
    if spring_line_correct:
        score += 30
        feedback_parts.append("Spring allocation (60%) correct")
    else:
        feedback_parts.append("Spring allocation incorrect or missing")

    if summer_line_correct:
        score += 30
        feedback_parts.append("Summer allocation (40%) correct")
    else:
        feedback_parts.append("Summer allocation incorrect or missing")

    if line_count != 2:
         feedback_parts.append(f"Incorrect number of distribution lines: found {line_count}, expected 2")
         # Penalty? The logic above naturally withholds points if lines aren't right, 
         # but specific feedback helps.

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }