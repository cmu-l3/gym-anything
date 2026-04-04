#!/usr/bin/env python3
"""Verifier for implement_isolated_workspace task."""

import json
import tempfile
import os

def verify_isolated_workspace(traj, env_info, task_info):
    """
    Verify that an isolated workspace was created and the layer is correctly hidden/shown.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/isolated_workspace_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce check fails, we fail the task to prevent gaming
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce verification failed"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Creation & Isolation (30 pts)
    ws_exists = result.get('workspace_exists', False)
    is_isolated = result.get('is_isolated', False)
    
    if ws_exists:
        if is_isolated:
            score += 30
            feedback_parts.append("Workspace 'alpha_corp' created and set to ISOLATED")
        else:
            score += 10
            feedback_parts.append("Workspace 'alpha_corp' created but NOT isolated")
    else:
        feedback_parts.append("Workspace 'alpha_corp' NOT found")

    # 2. Layer Published & Enabled (30 pts)
    layer_exists = result.get('layer_exists', False)
    layer_enabled = result.get('layer_enabled', False)
    
    if layer_exists and layer_enabled:
        score += 30
        feedback_parts.append("Layer 'secure_rivers' published and enabled")
    elif layer_exists:
        score += 15
        feedback_parts.append("Layer 'secure_rivers' published but disabled")
    else:
        feedback_parts.append("Layer 'secure_rivers' NOT found")

    # 3. Isolation Verification (40 pts total)
    visible_global = result.get('visible_in_global', True)
    visible_virtual = result.get('visible_in_virtual', False)
    
    # Should NOT be in global (20 pts)
    if not visible_global:
        # Only award if layer actually exists (otherwise it's hidden because it's missing)
        if layer_exists and layer_enabled:
            score += 20
            feedback_parts.append("Layer successfully hidden from Global WFS")
    else:
        feedback_parts.append("Layer leaked in Global WFS (Isolation failed)")

    # Should BE in virtual (20 pts)
    if visible_virtual:
        score += 20
        feedback_parts.append("Layer visible in Virtual WFS")
    else:
        if layer_exists:
            feedback_parts.append("Layer NOT visible in Virtual WFS")

    # Anti-gaming: Ensure GUI was used (check logs via result flag)
    # If the user script detected no GUI interaction, we might deduct points or fail
    # For now, we'll just note it in feedback unless VLM also fails
    gui_detected = result.get('gui_interaction_detected', False)
    if not gui_detected:
        feedback_parts.append("(Note: No GUI interaction detected in logs)")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }