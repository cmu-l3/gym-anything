#!/usr/bin/env python3
"""
Verifier for bulk_user_import_api task.

Evaluates:
1. Database confirmation of imported users (50 pts)
2. Accurate field mapping from CSV to SEB Server format (20 pts)
3. Python Script created/modified during session (10 pts)
4. Admin account intact (10 pts)
5. VLM verification of IDE/Terminal usage (10 pts)
"""

import os
import json
import tempfile
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Fallback VLM query if module can be imported
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM module not available. VLM checks will be skipped or stubbed.")

def verify_bulk_user_import_api(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_users = metadata.get('expected_users', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported results
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

    imported_users = result.get("imported_users", {})
    python_scripts = result.get("python_scripts_found", [])
    admin_exists = result.get("admin_exists", False)
    
    # CRITERION 1: Users exist in Database (50 points, 10 pts per user)
    users_found_count = 0
    for eu in expected_users:
        un = eu["username"]
        if un in imported_users:
            users_found_count += 1
            
    points_user_existence = users_found_count * 10
    score += points_user_existence
    feedback_parts.append(f"Users created: {users_found_count}/{len(expected_users)}")

    # CRITERION 2: Field Mapping (20 points, 4 pts per user with perfect mapping)
    perfect_mappings = 0
    for eu in expected_users:
        un = eu["username"]
        if un in imported_users:
            db_u = imported_users[un]
            if (db_u.get("name") == eu["name"] and 
                db_u.get("surname") == eu["surname"] and 
                db_u.get("email") == eu["email"]):
                perfect_mappings += 1

    points_field_mapping = perfect_mappings * 4
    score += points_field_mapping
    feedback_parts.append(f"Correct mappings: {perfect_mappings}/{len(expected_users)}")

    # CRITERION 3: Python Script Artifact (10 points)
    if len(python_scripts) > 0:
        score += 10
        feedback_parts.append(f"Script artifact found: {os.path.basename(python_scripts[0])}")
    else:
        feedback_parts.append("No Python script artifact found")

    # CRITERION 4: Data Integrity (Admin exists) (10 points)
    if admin_exists:
        score += 10
        feedback_parts.append("Admin account intact")
    else:
        feedback_parts.append("WARNING: Admin account missing!")

    # CRITERION 5: VLM Trajectory Verification for Automation (10 points)
    # Check if a terminal or IDE was used during the trajectory to write/execute code
    vlm_points = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = (
                    "Look at these screenshots from a computer agent's session. "
                    "Did the agent use a text editor, IDE (like VSCode), or a terminal emulator "
                    "to write or execute Python code? "
                    "Reply with exactly 'YES' if code writing or a terminal is visible, or 'NO' if not."
                )
                vlm_response = query_vlm(images=frames, prompt=prompt)
                if vlm_response and "YES" in vlm_response.upper():
                    vlm_points = 10
                    feedback_parts.append("VLM confirmed coding activity")
                else:
                    feedback_parts.append("VLM did not observe coding activity")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("VLM check error")
    else:
        # If VLM is not available, we give points if the script artifact was found (fallback)
        if len(python_scripts) > 0:
            vlm_points = 10
            feedback_parts.append("VLM skipped, awarded via artifact")
            
    score += vlm_points

    # Determine passing status: Minimum 80 points requires script automation and accurate DB insertions
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "users_found": users_found_count,
            "perfect_mappings": perfect_mappings,
            "script_found": len(python_scripts) > 0
        }
    }