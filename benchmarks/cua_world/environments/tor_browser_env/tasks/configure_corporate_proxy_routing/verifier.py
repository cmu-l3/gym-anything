#!/usr/bin/env python3
"""
Verifier for configure_corporate_proxy_routing task.

Verifies that:
1. The agent configured the proxy natively via Tor Browser Settings (updating active torrc).
2. The agent located and backed up the torrc file to the requested location.
3. The backup file was created during the task run (anti-gaming).
4. VLM Trajectory (if available) confirms the settings page was used.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_corporate_proxy_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_directive = metadata.get('expected_proxy_directive', 'HTTPSProxy 10.200.5.99:8080')
    backup_path = metadata.get('backup_path', '/home/ga/Documents/torrc_backup.txt')

    # Copy task_result.json securely from the container
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_file.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp_file.name)
            with open(tmp_file.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result file: {e}")
            return {"passed": False, "score": 0, "feedback": f"Could not load verification data: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    logger.info(f"Verification Data: {json.dumps(result, indent=2)}")

    score = 0
    feedback_parts = []

    # Criterion 1: Active torrc updated (40 points, GATE REQUIREMENT)
    active_torrc_has_proxy = result.get('active_torrc_has_proxy', False)
    if active_torrc_has_proxy:
        score += 40
        feedback_parts.append(f"Active torrc successfully updated with {expected_directive} (40/40)")
    else:
        feedback_parts.append(f"Active torrc does NOT contain {expected_directive} (0/40) - GATE FAILED")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Backup file exists (20 points)
    backup_exists = result.get('backup_exists', False)
    if backup_exists:
        score += 20
        feedback_parts.append(f"Backup file {backup_path} exists (20/20)")
    else:
        feedback_parts.append(f"Backup file {backup_path} NOT found (0/20)")

    # Criterion 3: Backup file is recent/created during task (20 points)
    backup_recent = result.get('backup_created_during_task', False)
    if backup_recent:
        score += 20
        feedback_parts.append("Backup file verified as created/modified during this task run (20/20)")
    elif backup_exists:
        feedback_parts.append("Backup file predates task start (Possible cheating) (0/20)")

    # Criterion 4: Backup file contents match expected config (20 points)
    backup_has_proxy = result.get('backup_has_proxy', False)
    if backup_has_proxy:
        score += 20
        feedback_parts.append("Backup file contains the correct proxy directive (20/20)")
    elif backup_exists:
        feedback_parts.append("Backup file content is incorrect or missing the proxy directive (0/20)")

    # VLM Trajectory Verification (Optional but recommended for robust anti-gaming)
    # We attempt to use VLM to verify the agent actually opened the settings UI
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Review these trajectory frames from a Tor Browser task. "
            "Did the user at any point open the Tor Browser Settings or Connection preferences panel "
            "to configure proxy settings? Answer ONLY 'YES' or 'NO'."
        )
        
        vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_resp and "YES" in vlm_resp.upper():
            logger.info("VLM Trajectory Verification: Passed (Settings opened)")
            feedback_parts.append("VLM confirmed interaction with Settings UI")
        else:
            logger.warning("VLM Trajectory Verification: Failed or Uncertain")
            feedback_parts.append("VLM could not confirm interaction with Settings UI")
    except ImportError:
        logger.info("VLM libraries unavailable; skipping trajectory visual verification.")
    except Exception as e:
        logger.warning(f"VLM trajectory verification encountered an error: {e}")

    # Determine final pass status
    # Pass threshold: 60 points + active torrc updated + backup exists + recent
    key_criteria_met = active_torrc_has_proxy and backup_exists and backup_recent
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }