#!/usr/bin/env python3
"""
Verifier for enable_web_statistics task.

Criteria:
1. Feature Enabled (30 pts): Webalizer reporting is enabled for the domain.
2. Report Exists (30 pts): index.html exists in stats directory.
3. Content Valid (20 pts): File contains expected Webalizer headers.
4. Freshness (20 pts): File was generated *during* the task (anti-gaming).

Pass Threshold: 80 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_web_statistics(traj, env_info, task_info):
    # Setup copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: Feature Enabled (30 pts)
    if result.get('feature_enabled', False):
        score += 30
        feedback_parts.append("Webalizer feature enabled (+30)")
    else:
        feedback_parts.append("Webalizer feature NOT enabled")

    # Criterion 2: Report Exists (30 pts)
    if result.get('report_exists', False):
        score += 30
        feedback_parts.append("Report file exists (+30)")
    else:
        feedback_parts.append("Report file NOT found")

    # Criterion 3: Content Valid (20 pts)
    # Only checks if report exists, otherwise meaningless
    if result.get('report_exists', False):
        if result.get('content_valid', False):
            score += 20
            feedback_parts.append("Report content valid (+20)")
        else:
            feedback_parts.append("Report content invalid/empty")
            
        # Criterion 4: Freshness (20 pts)
        if result.get('report_created_during_task', False):
            score += 20
            feedback_parts.append("Report generated during task (+20)")
        else:
            feedback_parts.append("Report is stale/old (anti-gaming check failed)")

    # Check for empty/dummy report
    if result.get('report_size', 0) < 100:
        score = min(score, 30) # Cap score if file is suspiciously small
        feedback_parts.append("WARNING: Report file is too small")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }