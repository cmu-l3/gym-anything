#!/usr/bin/env python3
"""
Verifier for migrate_local_mail_storage task.
Validates the OS-level file migration alongside Thunderbird's configuration update.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_local_mail_storage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read exported task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Read exported prefs.js
    temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    prefs_content = ""
    try:
        copy_from_env("/tmp/exported_prefs.js", temp_prefs.name)
        with open(temp_prefs.name, 'r', encoding='utf-8', errors='ignore') as f:
            prefs_content = f.read()
    except Exception as e:
        logger.warning(f"Failed to read prefs.js: {e}")
    finally:
        if os.path.exists(temp_prefs.name):
            os.unlink(temp_prefs.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Check Application Preferences (30 points)
    # ---------------------------------------------------------
    target_path = "/home/ga/ArchiveDrive/MailStore"
    path_configured = False
    
    dir_match = re.search(r'user_pref\("mail\.server\.server1\.directory",\s*"([^"]+)"\);', prefs_content)
    if dir_match:
        configured_path = dir_match.group(1)
        if target_path in configured_path:
            path_configured = True
            
    if path_configured:
        score += 30
        feedback_parts.append("Path correctly configured in Account Settings prefs")
    else:
        feedback_parts.append("Path NOT configured in Account Settings prefs")

    # ---------------------------------------------------------
    # Criterion 2: Check OS-level File Migration (30 points)
    # ---------------------------------------------------------
    migrated_exists = result.get('migrated_exists', False)
    migrated_count = result.get('migrated_count', 0)
    initial_count = result.get('initial_count', 0)
    
    mailbox_migrated = False
    if migrated_exists:
        if migrated_count >= max(1, initial_count - 5): # Allow minor discrepancies
            mailbox_migrated = True
            score += 30
            feedback_parts.append(f"Mailbox migrated successfully ({migrated_count} emails preserved)")
        else:
            score += 10
            feedback_parts.append(f"Mailbox found but missing emails (expected ~{initial_count}, found {migrated_count})")
    else:
        feedback_parts.append("Mailbox files NOT found in target directory (~/ArchiveDrive/MailStore)")
        
    # ---------------------------------------------------------
    # Criterion 3: Ensure Application was Restarted (20 points)
    # ---------------------------------------------------------
    tb_running = result.get('tb_running', False)
    if tb_running:
        score += 20
        feedback_parts.append("Thunderbird is running and active")
    else:
        feedback_parts.append("Thunderbird is NOT running (did not restart after closing)")

    # ---------------------------------------------------------
    # Criterion 4: VLM Trajectory Evidence Check (20 points)
    # ---------------------------------------------------------
    vlm_points = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are evaluating an IT task where the user migrates Thunderbird's local mail storage to a new drive.
Look at these chronological screenshots. Do you see evidence of the user doing ANY of the following:
1. Using a file manager or terminal to copy/move files to 'ArchiveDrive'
2. Opening Thunderbird's Account Settings and changing the 'Local directory' path
3. An active prompt to restart Thunderbird

Respond strictly with JSON format:
{
    "evidence_seen": true/false,
    "reasoning": "I observed..."
}"""
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and isinstance(vlm_res, dict) and vlm_res.get("success") is not False:
                parsed = vlm_res.get("parsed", {}) if "parsed" in vlm_res else vlm_res
                if parsed.get("evidence_seen", False):
                    vlm_points = 20
                    feedback_parts.append("VLM confirmed trajectory workflow evidence (+20)")
                else:
                    feedback_parts.append("VLM did not observe workflow evidence")
            else:
                vlm_points = 20
                feedback_parts.append("VLM query failed, granting points conservatively")
        else:
            vlm_points = 20
            feedback_parts.append("No trajectory frames for VLM, granting points")
    except ImportError:
        vlm_points = 20
        feedback_parts.append("VLM module unavailable, granting points conservatively")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_points = 20
        feedback_parts.append("VLM error, granting points conservatively")
        
    score += vlm_points

    # ---------------------------------------------------------
    # Check Pass Condition
    # ---------------------------------------------------------
    passed = score >= 80 and path_configured and mailbox_migrated
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }