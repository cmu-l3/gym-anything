#!/usr/bin/env python3
"""
Verifier for verify_pharmacy_dscsa_datamatrix task.

Verification Strategy:
1. File Verification: Checks if 'dscsa_log.txt' exists and was modified after the task started (anti-gaming).
2. Content Verification: Uses regular expressions to ensure the GTIN, EXP, and LOT components 
   were parsed strictly and formatted exactly as requested.
3. State Verification: Checks if the DataMatrix flag was enabled in bcWebCam's registry.
4. Trajectory Verification (VLM): Samples trajectory frames to confirm settings were opened.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dscsa_datamatrix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_gtin = metadata.get('expected_gtin', '00300010633215')
    expected_exp = metadata.get('expected_exp', '260531')
    expected_lot = metadata.get('expected_lot', 'BXL99')

    # Copy export result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/workspace/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result from environment: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criteria 1: File Exists & Anti-Gaming
    log_exists = result.get('log_exists', False)
    log_created_during_task = result.get('log_created_during_task', False)
    
    if log_exists and log_created_during_task:
        score += 20
        feedback_parts.append("Log file created during task (+20)")
    elif log_exists:
        feedback_parts.append("Log file exists but was NOT created/modified during task (Gaming attempt detected)")
    else:
        feedback_parts.append("Log file missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criteria 2: Application Configuration State
    datamatrix_enabled = result.get('datamatrix_enabled_in_reg', False)
    if datamatrix_enabled:
        score += 10
        feedback_parts.append("DataMatrix setting enabled (+10)")
    else:
        feedback_parts.append("DataMatrix setting was not enabled in bcWebCam registry")

    # Criteria 3: Content parsing
    content = result.get('log_content', '')
    
    # Strict Regex checks for EXACT formatting requested
    gtin_pattern = rf"^GTIN:\s*{re.escape(expected_gtin)}$"
    exp_pattern  = rf"^EXP:\s*{re.escape(expected_exp)}$"
    lot_pattern  = rf"^LOT:\s*{re.escape(expected_lot)}$"
    
    gtin_match = bool(re.search(gtin_pattern, content, re.MULTILINE | re.IGNORECASE))
    exp_match  = bool(re.search(exp_pattern, content, re.MULTILINE | re.IGNORECASE))
    lot_match  = bool(re.search(lot_pattern, content, re.MULTILINE | re.IGNORECASE))
    
    if gtin_match:
        score += 20
        feedback_parts.append("GTIN correctly parsed (+20)")
    else:
        feedback_parts.append("GTIN missing or incorrectly formatted")
        
    if exp_match:
        score += 20
        feedback_parts.append("EXP correctly parsed (+20)")
    else:
        feedback_parts.append("EXP missing or incorrectly formatted")
        
    if lot_match:
        score += 20
        feedback_parts.append("LOT correctly parsed (+20)")
    else:
        feedback_parts.append("LOT missing or incorrectly formatted")

    # Extra format bonus if it contains exactly those three lines and nothing else 
    # (Allowing for empty lines or whitespace)
    clean_lines = [line.strip() for line in content.split('\n') if line.strip()]
    if len(clean_lines) == 3 and gtin_match and exp_match and lot_match:
        score += 10
        feedback_parts.append("Strict formatting followed (+10)")

    # Criteria 4: VLM Verification of workflow (Optional redundancy)
    vlm_score_bonus = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = (
                "You are reviewing an agent's workflow in bcWebCam. "
                "Did the agent open the 'Settings' or 'Barcode Options' window at any point in these frames? "
                "Respond in JSON format: {\"settings_opened\": true/false}"
            )
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("settings_opened"):
                    vlm_score_bonus = 0 # No extra points, but good to log
                    feedback_parts.append("VLM confirmed settings window interaction")
                else:
                    feedback_parts.append("VLM did not observe settings window interaction")
    except ImportError:
        logger.info("VLM utilities not available, skipping VLM trajectory verification.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Determine pass/fail
    # Must have the file, the GTIN, and at least 60 points
    passed = log_exists and gtin_match and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }