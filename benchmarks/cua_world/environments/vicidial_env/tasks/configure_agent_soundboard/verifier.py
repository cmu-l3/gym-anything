#!/usr/bin/env python3
"""
Verifier for configure_agent_soundboard task.

Criteria:
1. System Settings: 'agent_soundboards' and 'central_sound_control_active' must be '1' (20 pts).
2. Soundboard Created: ID 'LEGAL_SB' exists in database (30 pts).
3. Audio Uploaded: 'legal_disclosure' exists in audio store/disk (20 pts).
4. Audio Linked: Association exists between 'LEGAL_SB' and 'legal_disclosure' (30 pts).

Pass threshold: 80 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_agent_soundboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify System Settings (20 pts)
    # Both must be '1' to get points.
    settings = result.get("settings", {})
    sb_setting = str(settings.get("agent_soundboards", "0"))
    central_setting = str(settings.get("central_sound_control", "0"))
    
    if sb_setting == "1" and central_setting == "1":
        score += 20
        feedback_parts.append("System settings correctly enabled.")
    else:
        feedback_parts.append(f"System settings incorrect (SB: {sb_setting}, Central: {central_setting}).")

    # 3. Verify Soundboard Creation (30 pts)
    sb_data = result.get("soundboard", {})
    if int(sb_data.get("exists_count", 0)) > 0:
        score += 30
        feedback_parts.append("Soundboard 'LEGAL_SB' created.")
    else:
        feedback_parts.append("Soundboard 'LEGAL_SB' NOT found.")

    # 4. Verify Audio Upload (20 pts)
    # Check both DB record and disk existence, allow either to count partial or full
    audio_data = result.get("audio", {})
    db_exists = int(audio_data.get("db_record_exists", 0)) > 0
    disk_exists = int(audio_data.get("file_on_disk", 0)) > 0
    
    if db_exists or disk_exists:
        score += 20
        feedback_parts.append("Audio file uploaded successfully.")
    else:
        feedback_parts.append("Audio file upload failed or not found.")

    # 5. Verify Linkage (30 pts)
    link_data = result.get("linkage", {})
    if int(link_data.get("count", 0)) > 0:
        score += 30
        feedback_parts.append("Audio correctly linked to Soundboard.")
    else:
        feedback_parts.append("Audio NOT linked to Soundboard.")

    # 6. Final Score Calculation
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }