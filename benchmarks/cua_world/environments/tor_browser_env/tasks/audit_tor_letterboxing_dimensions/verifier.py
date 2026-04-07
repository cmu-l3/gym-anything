#!/usr/bin/env python3
"""Verifier for audit_tor_letterboxing_dimensions task.

Evaluates if the agent used DevTools to measure viewport, disabled letterboxing
via about:config, remeasured, and accurately compiled the text report.
Includes VLM validation of trajectories.
"""

import json
import logging
import os
import re
import tempfile

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "audit_tor_letterboxing_dimensions"

def verify_letterboxing_audit(traj, env_info, task_info):
    """
    Verification strategy:
    1. prefs.js modified correctly (Gate: MUST BE TRUE) - 40 pts
    2. Audit file exists & was created during task - 15 pts
    3. File contains all 4 formatting fields - 15 pts
    4. Valid numerical extraction - 10 pts
    5. Logical consistency (Unconstrained >= Letterboxed) - 10 pts
    6. Trajectory/History verification - 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # 1. Gate: prefs.js modified (40 points)
    prefs_updated = result.get('letterboxing_false_in_prefs', False)
    if prefs_updated:
        score += 40
        feedback_parts.append("privacy.resistFingerprinting.letterboxing set to false (40/40)")
    else:
        feedback_parts.append("FAIL: privacy.resistFingerprinting.letterboxing NOT set to false in prefs.js")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Audit file existence and recency (15 points)
    file_exists = result.get('audit_file_exists', False)
    file_is_new = result.get('audit_file_is_new', False)
    content = result.get('audit_file_content', '')

    if file_exists and file_is_new:
        score += 15
        feedback_parts.append("Audit file created during task (15/15)")
    elif file_exists:
        score += 5
        feedback_parts.append("Audit file exists but may pre-date task (5/15)")
    else:
        feedback_parts.append("Audit file NOT found (0/15)")

    # 3 & 4. Extraction and Validation (25 points)
    # Target regexes
    lw_pattern = re.compile(r'Letterboxed Width:\s*(\d+)', re.IGNORECASE)
    lh_pattern = re.compile(r'Letterboxed Height:\s*(\d+)', re.IGNORECASE)
    uw_pattern = re.compile(r'Unconstrained Width:\s*(\d+)', re.IGNORECASE)
    uh_pattern = re.compile(r'Unconstrained Height:\s*(\d+)', re.IGNORECASE)

    m_lw = lw_pattern.search(content)
    m_lh = lh_pattern.search(content)
    m_uw = uw_pattern.search(content)
    m_uh = uh_pattern.search(content)

    all_labels_present = all([m_lw, m_lh, m_uw, m_uh])

    if all_labels_present:
        score += 15
        feedback_parts.append("All 4 formatting fields found (15/15)")
        
        try:
            lw = int(m_lw.group(1))
            lh = int(m_lh.group(1))
            uw = int(m_uw.group(1))
            uh = int(m_uh.group(1))
            
            score += 10
            feedback_parts.append("Valid integers extracted (10/10)")
            
            # 5. Logical consistency check (10 points)
            # Unconstrained window should be larger or at least equal to letterboxed inner window
            if uw >= lw and uh >= lh and (lw > 0 and lh > 0):
                score += 10
                feedback_parts.append("Dimensions logic correct: Unconstrained >= Letterboxed (10/10)")
            else:
                feedback_parts.append(f"Dimensions logic failed: Letterboxed({lw}x{lh}) vs Unconstrained({uw}x{uh}) (0/10)")
                
        except ValueError:
            feedback_parts.append("Failed to parse extracted values as integers (0/20)")
    elif file_exists:
        feedback_parts.append("Missing required fields or labels in text file (0/25)")

    # 6. History / Trajectory verification (10 points)
    # Check if target site was visited
    history_ok = result.get('history_has_check_torproject', False)
    
    # Optional VLM check to ensure DevTools or about:config was opened
    vlm_used_devtools_or_config = False
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = ("Analyze this screenshot of Tor Browser. Does it show EITHER "
                      "the Web Developer Tools (Console, Inspector, etc.) OR the 'about:config' "
                      "advanced preferences page? Answer YES or NO.")
            responses = query_vlm(images=frames, prompt=prompt)
            for resp in responses:
                if 'YES' in resp.upper():
                    vlm_used_devtools_or_config = True
                    break
    except Exception as e:
        logger.warning(f"VLM trajectory check failed or unavailable: {e}")

    if history_ok or vlm_used_devtools_or_config:
        score += 10
        feedback_parts.append("Trajectory/History validated (10/10)")
    else:
        feedback_parts.append("Trajectory validation incomplete: target page/devtools not detected (0/10)")

    passed = (score >= 60 and prefs_updated)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }