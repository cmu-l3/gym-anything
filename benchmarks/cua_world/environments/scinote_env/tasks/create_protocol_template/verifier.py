#!/usr/bin/env python3
"""Verifier for create_protocol_template task."""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Ensure we can import the VLM utilities
import sys
sys.path.append("/workspace/scripts")
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    print("Warning: VLM utilities not available.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_trajectory_with_vlm(traj: list, task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Use VLM to verify that the agent interacted with the protocol repository UI."""
    if not VLM_AVAILABLE or not traj:
        return {"success": False, "score": 0, "reason": "VLM not available or empty trajectory"}

    # Sample up to 4 frames from the trajectory
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        return {"success": False, "score": 0, "reason": "No frames to analyze"}

    prompt = """You are analyzing an agent's trajectory while using the SciNote Electronic Lab Notebook.
The agent's task was to create a new protocol template named 'Western Blot Protocol' in the Protocols repository.

Look at these sequential screenshots and verify:
1. Did the agent navigate to the 'Protocols' section of the application?
2. Is there evidence of the agent using the protocol editor (adding steps, typing text, or setting a description)?
3. Can you see the words 'Western Blot Protocol' or related steps ('Sample Preparation', 'Gel Electrophoresis') being entered?

Respond in JSON format:
{
    "navigated_to_protocols": true/false,
    "used_protocol_editor": true/false,
    "entered_western_blot_content": true/false,
    "confidence": "high/medium/low",
    "explanation": "Brief reasoning"
}
"""
    try:
        vlm_result = query_vlm(images=frames, prompt=prompt)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            criteria_met = sum([
                parsed.get("navigated_to_protocols", False),
                parsed.get("used_protocol_editor", False),
                parsed.get("entered_western_blot_content", False)
            ])
            # Give points based on UI interaction evidence (max 15 pts)
            score = int((criteria_met / 3.0) * 15)
            return {"success": True, "score": score, "parsed": parsed}
    except Exception as e:
        logger.error(f"VLM error: {e}")
    
    return {"success": False, "score": 0, "reason": "VLM failure"}


def verify_create_protocol_template(traj, env_info, task_info):
    """Verify that the Western Blot protocol template was created correctly in the repository."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_protocol_name', 'Western Blot Protocol')
    expected_desc = metadata.get('expected_description', 'Standard Western Blot protocol for protein detection and analysis')
    expected_step1 = metadata.get('expected_step1_name', 'Sample Preparation')
    expected_step2 = metadata.get('expected_step2_name', 'Gel Electrophoresis')
    expected_step3 = metadata.get('expected_step3_name', 'Transfer and Detection')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_protocol_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    protocol_found = result.get('protocol_found', False)
    protocol = result.get('protocol', {})
    steps = protocol.get('steps', [])

    # Criterion 1: Protocol exists in repository (25 pts)
    if protocol_found:
        score += 25
        feedback_parts.append(f"Protocol '{expected_name}' found in repository")
    else:
        feedback_parts.append(f"Protocol '{expected_name}' not found in repository")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Anti-gaming: Ensure it was created, not pre-existing
    initial_count = int(result.get('initial_repo_protocol_count', 0))
    current_count = int(result.get('current_repo_protocol_count', 0))
    if current_count > initial_count:
        score += 5
        feedback_parts.append("Protocol count increased appropriately")
    else:
        feedback_parts.append("Warning: Protocol count did not increase")

    # Criterion 2: Description is present and correct (10 pts)
    actual_desc = protocol.get('description', '')
    if actual_desc and actual_desc.strip() != "":
        score += 10
        if expected_desc.lower() in actual_desc.lower():
            feedback_parts.append("Description matches exactly")
        else:
            feedback_parts.append("Description is populated (partial text match)")
    else:
        feedback_parts.append("Protocol description is missing")

    # Criterion 3: Step Count >= 3 (15 pts)
    step_count = protocol.get('step_count', 0)
    if step_count >= 3:
        score += 15
        feedback_parts.append(f"Protocol has correct number of steps ({step_count})")
    elif step_count > 0:
        score += int((step_count / 3.0) * 15)
        feedback_parts.append(f"Protocol has partial steps ({step_count}/3)")
    else:
        feedback_parts.append("Protocol has no steps")

    # Build lookup by step name
    step_lookup = {s.get('name', '').strip().lower(): s for s in steps}
    
    # Criterion 4-6: Step Names and Contents Correct (10 pts each = 30 pts)
    for expected_step, pts in [(expected_step1, 10), (expected_step2, 10), (expected_step3, 10)]:
        if expected_step.strip().lower() in step_lookup:
            step_data = step_lookup[expected_step.strip().lower()]
            text_content = step_data.get('text_content', '')
            if text_content and len(text_content.strip()) > 5:
                score += pts
                feedback_parts.append(f"Step '{expected_step}' found with text content")
            else:
                score += int(pts / 2)
                feedback_parts.append(f"Step '{expected_step}' found but missing text content")
        else:
            feedback_parts.append(f"Step '{expected_step}' missing")

    # Criterion 7: VLM Trajectory Verification (15 pts)
    vlm_res = verify_trajectory_with_vlm(traj, task_info)
    if vlm_res.get("success"):
        score += vlm_res.get("score", 0)
        feedback_parts.append(f"VLM trajectory verification: {vlm_res.get('score')} pts")
    else:
        feedback_parts.append("VLM trajectory verification skipped or failed")

    passed = score >= 65 and protocol_found and step_count >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "protocol_created": protocol_found,
            "has_description": bool(actual_desc.strip()),
            "sufficient_steps": step_count >= 3,
            "vlm_verified": vlm_res.get("success", False)
        }
    }