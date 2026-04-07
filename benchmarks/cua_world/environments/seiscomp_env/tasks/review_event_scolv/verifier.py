#!/usr/bin/env python3
"""
Verifier for Expert Event Review (scolv) task.

Evaluation Strategy (Multi-Signal):
1. Database Integrity: Directly extracts and verifies SeisComP MySQL entities.
   - New origin created with manual 'GYM' agency and 13.0 km depth.
   - Magnitudes recomputed and actively linked to the new origin.
   - Event metadata updated (earthquake/known).
   - Expected textual comment appended.
2. VLM Trajectory (Optional Bonus/Confirmation): Confirms UI interactions.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Safely import VLM tools
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    sample_trajectory_frames = None
    get_final_screenshot = None


def verify_review_event_scolv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_depth = metadata.get('expected_depth_km', 13.0)
    depth_tol = metadata.get('depth_tolerance_km', 0.5)
    expected_agency = metadata.get('expected_agency', 'GYM')
    expected_type = metadata.get('expected_type', 'earthquake')
    expected_cert = metadata.get('expected_certainty', 'known')
    
    # 1. Retrieve DB JSON State
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

    score = 0
    feedback_parts = []
    
    event = result.get('event', {})
    origin = result.get('origin', {})
    mag = result.get('magnitude', {})
    comment_count = result.get('comment_count', 0)

    # 2. Check Origin Depth & Agency (35 pts)
    agency = origin.get('creationInfo_agencyID', '')
    try:
        depth = float(origin.get('depth_value', 0) or 0)
    except ValueError:
        depth = 0.0

    if agency == expected_agency:
        score += 15
        feedback_parts.append(f"Origin agency '{expected_agency}' detected")
        if abs(depth - expected_depth) <= depth_tol:
            score += 20
            feedback_parts.append(f"Depth fixed accurately to {depth} km")
        else:
            feedback_parts.append(f"Depth {depth} km outside acceptable tolerance")
    else:
        feedback_parts.append("Preferred origin not replaced by manual agent commit")

    # 3. Check Magnitudes (20 pts)
    mag_agency = mag.get('creationInfo_agencyID', '')
    mag_origin = mag.get('originID', '')
    pref_orig = event.get('preferredOriginID', 'NONE')

    if mag_agency == expected_agency and mag_origin == pref_orig and pref_orig != 'NONE':
        score += 20
        feedback_parts.append("Magnitudes recomputed and properly linked")
    else:
        feedback_parts.append("Magnitudes not updated for the new origin")

    # 4. Check Metadata Classification (15 pts)
    # Handle schema variations: could be 'type' and 'certainty', or 'typeCertainty'
    e_type = event.get('type', event.get('typeCertainty', '')).lower()
    e_cert = event.get('certainty', event.get('typeCertainty', '')).lower()
    
    if expected_type in e_type:
        score += 10
        feedback_parts.append("Event type updated to earthquake")
    if expected_cert in e_cert:
        score += 5
        feedback_parts.append("Event certainty updated to known")

    # 5. Check Audit Comment (10 pts)
    if comment_count >= 1:
        score += 10
        feedback_parts.append("Audit comment correctly added")

    # 6. VLM Check for UI Interaction Evidence (20 pts)
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    if query_vlm and sample_trajectory_frames and get_final_screenshot:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are analyzing an agent performing a manual earthquake review in SeisComP's 'scolv' application.
Look closely at the trajectory frames to verify UI interaction.

Assess:
1. Did the agent successfully open/view the scolv application?
2. Did the agent navigate through the primary tabs inside scolv (e.g., Location, Magnitudes, or Event tabs)?

Respond strictly in JSON format:
{
  "scolv_visible": true/false,
  "ui_interaction_confirmed": true/false
}"""
            vlm_response = query_vlm(prompt=prompt, images=images)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("scolv_visible"): vlm_score += 10
                if parsed.get("ui_interaction_confirmed"): vlm_score += 10
                score += vlm_score
                feedback_parts.append(f"VLM verification passed (+{vlm_score} pts)")
        except Exception as e:
            logger.warning(f"VLM trajectory verification skipped/failed: {e}")

    # Final Pass Evaluation
    # Agent must achieve at least 60 points and MUST have committed a change to Origin or Type
    key_criteria_met = (agency == expected_agency) or (expected_type in e_type)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }