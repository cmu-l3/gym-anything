#!/usr/bin/env python3
"""Verifier for Polite Crawl Configuration Profile task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_polite_crawl_configuration_profile(traj, env_info, task_info):
    """
    Verify the polite crawl configuration task.
    
    Scoring Criteria (100 pts total):
    1. Configuration file saved correctly (30 pts)
    2. Crawl data exported with correct content (30 pts)
    3. Speed settings screenshot created (20 pts)
    4. User-Agent settings screenshot created (20 pts)
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Criterion 1: Configuration File (30 pts)
    if result.get('config_exists', False):
        score += 30
        feedback_parts.append("Config file saved (30/30)")
    else:
        feedback_parts.append("Config file not found (0/30)")

    # Criterion 2: Export Data (30 pts)
    export_exists = result.get('export_exists', False)
    rows = result.get('export_rows', 0)
    has_domain = result.get('export_has_domain', False)
    
    if export_exists:
        if rows >= 5 and has_domain:
            score += 30
            feedback_parts.append(f"Export valid ({rows} rows) (30/30)")
        elif rows > 0:
            score += 15
            feedback_parts.append(f"Export exists but low row count/wrong domain (15/30)")
        else:
            score += 5
            feedback_parts.append("Export file exists but is empty (5/30)")
    else:
        feedback_parts.append("Export file not found (0/30)")

    # Criterion 3: Speed Screenshot (20 pts)
    if result.get('speed_screenshot_exists', False):
        score += 20
        feedback_parts.append("Speed screenshot found (20/20)")
    else:
        feedback_parts.append("Speed screenshot missing (0/20)")

    # Criterion 4: UA Screenshot (20 pts)
    if result.get('ua_screenshot_exists', False):
        score += 20
        feedback_parts.append("UA screenshot found (20/20)")
    else:
        feedback_parts.append("UA screenshot missing (0/20)")

    # VLM Verification (Optional but recommended for robust checking of screenshot content)
    # If we had VLM access, we would check if the screenshots actually show the dialogs.
    # For now, file existence is the proxy given the constraints.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }