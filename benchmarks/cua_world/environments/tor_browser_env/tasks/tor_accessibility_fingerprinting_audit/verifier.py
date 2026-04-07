#!/usr/bin/env python3
"""Verifier for tor_accessibility_fingerprinting_audit task.

Validates that the agent overrode Tor's accessibility block,
audited the A11y tree of check.torproject.org, and extracted specific properties.
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "tor_accessibility_fingerprinting_audit"
TARGET_FILE = "/home/ga/Documents/a11y_audit.txt"

def verify_a11y_audit(traj, env_info, task_info):
    """
    Verify the accessibility audit task was completed successfully.

    Scoring (100 points total):
    1. File exists & recent (Gate)        - 15 pts
    2. Status Element Role/Name matches   - 25 pts
    3. Donate Element Role/Name matches   - 25 pts
    4. A11y Pref Modified                 - 15 pts
    5. Target Bookmarked                  - 20 pts

    Pass threshold: 65+ points AND the report file must exist (Gate).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Copy JSON result
    json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    json_tmp.close()
    
    # 2. Copy Target Text File
    txt_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    txt_tmp.close()

    result = {}
    file_content = ""

    try:
        try:
            copy_from_env(f"/tmp/{TASK_NAME}_result.json", json_tmp.name)
            with open(json_tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read JSON result: {e}")

        try:
            copy_from_env(TARGET_FILE, txt_tmp.name)
            with open(txt_tmp.name, 'r', encoding='utf-8') as f:
                file_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to read target text file (might not exist): {e}")

    finally:
        if os.path.exists(json_tmp.name):
            os.unlink(json_tmp.name)
        if os.path.exists(txt_tmp.name):
            os.unlink(txt_tmp.name)

    logger.info(f"JSON Result: {json.dumps(result, indent=2)}")
    logger.info(f"File Content:\n{file_content}")

    score = 0
    feedback_parts = []

    # Criterion 1: File exists and is new
    file_exists = result.get('file_exists', False)
    file_is_new = result.get('file_is_new', False)

    if file_exists and file_is_new:
        score += 15
        feedback_parts.append("Report file created (15/15)")
    elif file_exists:
        feedback_parts.append("Report file exists but predates task (0/15)")
    else:
        feedback_parts.append("Report file missing (0/15)")
        # Gate failure
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) + " — Gate failed: output file is required."
        }

    # Criterion 2: Status Element Role/Name
    # Expected Role: heading (or h1-h6)
    # Expected Name: Congratulations. This browser is configured to use Tor.
    status_match = re.search(
        r'Status Element\s*-\s*Role:\s*(heading|h[1-6]).*?Name:\s*.*?(Congratulations|configured to use Tor)', 
        file_content, 
        re.IGNORECASE | re.DOTALL
    )
    if status_match:
        score += 25
        feedback_parts.append("Status Element A11y properties correct (25/25)")
    else:
        # Give partial credit if they at least attempted the Status Element line
        if re.search(r'Status Element\s*-', file_content, re.IGNORECASE):
            score += 10
            feedback_parts.append("Status Element properties incorrect or incomplete (10/25)")
        else:
            feedback_parts.append("Status Element properties missing (0/25)")

    # Criterion 3: Donate Element Role/Name
    # Expected Role: link (or a)
    # Expected Name: Donate to Support Tor (or similar 'Donate')
    donate_match = re.search(
        r'Donate Element\s*-\s*Role:\s*(link|a).*?Name:\s*.*?(Donate)', 
        file_content, 
        re.IGNORECASE | re.DOTALL
    )
    if donate_match:
        score += 25
        feedback_parts.append("Donate Element A11y properties correct (25/25)")
    else:
        if re.search(r'Donate Element\s*-', file_content, re.IGNORECASE):
            score += 10
            feedback_parts.append("Donate Element properties incorrect or incomplete (10/25)")
        else:
            feedback_parts.append("Donate Element properties missing (0/25)")

    # Criterion 4: A11y Pref Modified
    # The agent explicitly had to enable devtools accessibility or disable force_disabled
    if result.get('a11y_pref_modified', False):
        score += 15
        feedback_parts.append("A11y preferences overridden (15/15)")
    else:
        # Fallback: if they successfully extracted properties, they MUST have enabled it in memory.
        if status_match or donate_match:
            score += 15
            feedback_parts.append("A11y properties extracted, implying A11y enabled in memory (15/15)")
        else:
            feedback_parts.append("A11y preferences not modified (0/15)")

    # Criterion 5: Target Bookmarked
    if result.get('bookmark_target_exists', False):
        score += 20
        feedback_parts.append("Target page bookmarked correctly (20/20)")
    else:
        feedback_parts.append("Target page NOT bookmarked correctly (0/20)")

    # Final Evaluation
    passed = score >= 65 and file_exists and file_is_new
    
    logger.info(f"Score: {score}/100, Passed: {passed}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }