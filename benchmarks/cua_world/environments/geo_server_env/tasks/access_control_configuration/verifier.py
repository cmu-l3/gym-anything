#!/usr/bin/env python3
"""Verifier for access_control_configuration task.

A GIS Security Admin must:
1. Create user 'gis_reader'
2. Create role 'ROLE_GIS_READER'
3. Assign user to role
4. Create data ACL rule for ne.* giving ROLE_GIS_READER read access
5. Create WMS service security rule

Scoring (100 pts, pass >= 60):
- User 'gis_reader' exists:               20 pts
- Role 'ROLE_GIS_READER' exists:          20 pts
- User assigned to role:                  20 pts
- Data access rule for ne.* with role:    25 pts
- WMS service security rule exists:       15 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_access_control_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/access_control_configuration_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Nonce check
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce in result but nonce file unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- 1. User gis_reader exists (20 pts) ----
    if result.get('user_found'):
        score += 20
        subscores['user'] = True
        feedback_parts.append("User 'gis_reader' created successfully")
    else:
        feedback_parts.append("User 'gis_reader' NOT found")

    # ---- 2. Role ROLE_GIS_READER exists (20 pts) ----
    if result.get('role_found'):
        score += 20
        subscores['role'] = True
        feedback_parts.append("Role 'ROLE_GIS_READER' created successfully")
    else:
        feedback_parts.append("Role 'ROLE_GIS_READER' NOT found")

    # ---- 3. User assigned to role (20 pts) ----
    if result.get('role_assigned'):
        score += 20
        subscores['assignment'] = True
        feedback_parts.append("User 'gis_reader' assigned to 'ROLE_GIS_READER'")
    else:
        feedback_parts.append("User 'gis_reader' NOT assigned to 'ROLE_GIS_READER'")

    # Mandatory: user AND role must both exist
    if not result.get('user_found') and not result.get('role_found'):
        return {"passed": False, "score": score,
                "feedback": " | ".join(feedback_parts) + " | CRITICAL: user and role both missing"}

    # ---- 4. Data access rule for ne.* (25 pts) ----
    if result.get('data_rule_found'):
        score += 25
        subscores['data_rule'] = True
        feedback_parts.append(
            f"Data ACL rule found: '{result.get('data_rule_key')}' -> '{result.get('data_rule_value')}'"
        )
    elif result.get('data_rule_any'):
        # Has a rule with ROLE_GIS_READER but may not exactly match ne.*
        score += 12
        feedback_parts.append(
            f"Data ACL rule with ROLE_GIS_READER found (not matching ne.*): {result.get('data_rule_any')}"
        )
    else:
        feedback_parts.append("No data ACL rule found for ne workspace with ROLE_GIS_READER")

    # ---- 5. Service security rule for WMS (15 pts) ----
    if result.get('service_rule_found'):
        score += 15
        subscores['service_rule'] = True
        feedback_parts.append(
            f"WMS service rule configured: {result.get('service_rule_value')}"
        )
    elif result.get('service_rule_partial'):
        score += 8
        feedback_parts.append(
            f"WMS service rule found but may not include ROLE_GIS_READER: {result.get('service_rule_value')}"
        )
    else:
        feedback_parts.append("No WMS service security rule found")

    # ---- VLM trajectory ----
    vlm_gui_confirmed = True
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        vlm_gui_confirmed = False
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_first_screenshot, get_final_screenshot
            first = get_first_screenshot(traj)
            last = get_final_screenshot(traj)
            frames = sample_trajectory_frames(traj, num_samples=4)
            images = []
            if first:
                images.append(first)
            images.extend([f for f in frames if f not in images])
            if last and last not in images:
                images.append(last)
            if images:
                vlm_result = query_vlm(
                    images=images,
                    prompt=(
                        "A GIS admin is configuring security settings in GeoServer.\n"
                        "Check the following in screenshots:\n"
                        "1. 'user_form_used': Was a user creation/edit form visible?\n"
                        "2. 'role_form_used': Was a role creation form or role assignment interface visible?\n"
                        "3. 'security_rules_visited': Were Security/Data or Security/Services pages visited?\n"
                        "Return JSON: {\"user_form_used\": bool, \"role_form_used\": bool, \"security_rules_visited\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('user_form_used'):
                        vlm_pts += 4
                    if parsed.get('role_form_used'):
                        vlm_pts += 3
                    if parsed.get('security_rules_visited'):
                        vlm_pts += 3
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(f"VLM confirmed security workflow: {vlm_pts}/10 pts")
                    else:
                        feedback_parts.append("VLM: no security GUI interaction detected")
                else:
                    vlm_gui_confirmed = True
        except Exception:
            vlm_gui_confirmed = True

    gui_interaction = result.get('gui_interaction_detected', True)
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    # Must have both user and role for pass
    user_and_role = result.get('user_found') and result.get('role_found')
    passed = score >= PASS_THRESHOLD and user_and_role and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
