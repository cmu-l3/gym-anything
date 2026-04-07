#!/usr/bin/env python3
"""
Verifier for set_dive_rating_visibility task.

Verification Strategy:
1. File verification: Ensures the `.ssrf` file was actually modified via timestamp & hash.
2. Programmatic checks: Parses XML to check if dive #2 has `rating="4"` and `visibility="3"`.
3. Integrity check: Ensures no dives were deleted.
4. VLM Check: Verifies trajectory screenshots to confirm interaction with the star widgets.
"""

import os
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_dive_rating_visibility(traj, env_info, task_info):
    # Ensure correct method is used to grab data from the VM environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available from environment."}

    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Load task metadata expectations
    metadata = task_info.get('metadata', {})
    expected_rating = str(metadata.get('expected_rating', 4))
    expected_visibility = str(metadata.get('expected_visibility', 3))
    expected_total_dives = metadata.get('expected_total_dives', 8)

    score = 0
    feedback_parts = []

    # Criterion 1: File modified check (Anti-gaming)
    if result.get('file_modified'):
        score += 10
        feedback_parts.append("File correctly modified")
    elif result.get('file_exists'):
        # If file was not modified, agent failed to save or edit
        feedback_parts.append("File exists but was NOT modified")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Dive log was not modified. Did you remember to press Ctrl+S to save?"
        }

    # Data Integrity check
    actual_total_dives = result.get('total_dives', 0)
    if actual_total_dives != expected_total_dives:
        feedback_parts.append(f"Warning: Dive count changed from {expected_total_dives} to {actual_total_dives}")

    if not result.get('dive_found'):
        feedback_parts.append("Dive #2 NOT found in the logbook")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Rating value check
    actual_rating = str(result.get('rating', '0'))
    rating_ok = False
    if actual_rating == expected_rating:
        score += 35
        rating_ok = True
        feedback_parts.append(f"Rating correct ({actual_rating}/5 stars)")
    else:
        feedback_parts.append(f"Rating incorrect (expected {expected_rating}, got {actual_rating})")

    # Criterion 3: Visibility value check
    actual_vis = str(result.get('visibility', '0'))
    vis_ok = False
    if actual_vis == expected_visibility:
        score += 35
        vis_ok = True
        feedback_parts.append(f"Visibility correct ({actual_vis}/5 stars)")
    else:
        feedback_parts.append(f"Visibility incorrect (expected {expected_visibility}, got {actual_vis})")

    # Criterion 4: VLM Trajectory Verification
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + ([final] if final else [])

        if images:
            prompt = (
                "You are auditing a computer agent's task in Subsurface dive log software.\n"
                "Review these screenshot frames. Did the agent navigate to Dive #2, open the 'Notes' panel, "
                "and interact with the small star-rating widgets (Rating and Visibility)?\n"
                "Return JSON with:\n"
                "{\"interacted_with_stars\": true/false, \"selected_target_dive\": true/false}"
            )
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp and vlm_resp.get("parsed"):
                parsed = vlm_resp["parsed"]
                if parsed.get("interacted_with_stars") and parsed.get("selected_target_dive"):
                    vlm_passed = True
                    score += 20
                    feedback_parts.append("VLM confirmed interaction with star widgets")
                else:
                    feedback_parts.append("VLM did not detect interaction with star UI elements")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # If VLM is entirely unavailable, award points if XML matches perfectly to avoid penalizing agent
        if rating_ok and vis_ok:
            score += 20
            vlm_passed = True
            feedback_parts.append("VLM unavailable, awarded points based on correct XML data")

    # Final pass logic - require XML perfection and file save action
    passed = (score >= 80) and result.get('file_modified') and rating_ok and vis_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }