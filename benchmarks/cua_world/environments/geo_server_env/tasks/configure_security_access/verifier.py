#!/usr/bin/env python3
"""Verifier for configure_security_access task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_security_access(traj, env_info, task_info):
    """
    Verify GeoServer security configuration.
    
    Criteria:
    1. Role 'map_editor' exists (20 pts)
    2. User 'editor1' exists and is enabled (20 pts)
    3. User 'editor1' has 'map_editor' role (25 pts)
    4. Access rule 'ne.*.w' exists and has correct roles (35 pts)
    
    Pass Threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_security_access_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Integrity check
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce file is missing in container but result has one, suspicious
        if result.get('result_nonce'):
             return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce check failed"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Role (20 pts)
    if result.get('role_exists'):
        score += 20
        feedback_parts.append("Role 'map_editor' created")
    else:
        feedback_parts.append("Role 'map_editor' NOT found")

    # 2. Check User (20 pts)
    if result.get('user_exists'):
        if result.get('user_enabled'):
            score += 20
            feedback_parts.append("User 'editor1' created and enabled")
        else:
            score += 10
            feedback_parts.append("User 'editor1' created but DISABLED")
    else:
        feedback_parts.append("User 'editor1' NOT found")

    # 3. Check Assignment (25 pts)
    if result.get('role_assigned'):
        score += 25
        feedback_parts.append("Role 'map_editor' correctly assigned to 'editor1'")
    else:
        feedback_parts.append("Role NOT assigned to user")

    # 4. Check Rule (35 pts)
    rule_data = result.get('rule_check', {})
    if rule_data.get('exists'):
        sub_score = 0
        rule_feedback = []
        
        # Rule exists, check contents
        if rule_data.get('has_editor'):
            sub_score += 20
            rule_feedback.append("map_editor granted")
        else:
            rule_feedback.append("map_editor MISSING")
            
        if rule_data.get('has_admin'):
            sub_score += 15
            rule_feedback.append("ROLE_ADMINISTRATOR granted")
        else:
            rule_feedback.append("ROLE_ADMINISTRATOR MISSING")
            
        score += sub_score
        feedback_parts.append(f"Rule 'ne.*.w' found: {', '.join(rule_feedback)}")
    else:
        feedback_parts.append("Access rule 'ne.*.w' NOT found")

    # VLM Verification (Trajectory Analysis)
    # Check if we should enforce GUI usage or verify specific steps
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, num_samples=4)
        final = get_final_screenshot(traj)
        
        images = []
        if frames: images.extend(frames)
        if final: images.append(final)
        
        if images:
            # Simple check: did the agent access the security page?
            vlm_res = query_vlm(
                images=images,
                prompt="Do these screenshots show the GeoServer Security configuration interface (Users, Roles, or Data Security pages)? Return JSON: {\"security_interface_visible\": bool}"
            )
            
            if vlm_res and isinstance(vlm_res, dict) and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('security_interface_visible'):
                    feedback_parts.append("VLM confirmed security interface usage")
                else:
                    feedback_parts.append("VLM: Security interface not clearly visible")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }