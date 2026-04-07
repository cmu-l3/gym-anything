#!/usr/bin/env python3
"""Verifier for muybridge_stop_motion_html task.

Checks that the agent used ImageMagick to compile the frames into a 500px, 100ms
animated GIF, embedded it in an HTML page with specific CSS, and viewed it.
Includes a VLM verification check on the trajectory to confirm visual rendering.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_muybridge_stop_motion(traj, env_info, task_info):
    """Verify GIF assembly and HTML creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/muybridge_analysis.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: GIF Exists and Modified (10 pts)
    if result.get("gif_exists"):
        if result.get("gif_modified"):
            score += 10
            feedback.append("horse_motion.gif created")
        else:
            feedback.append("horse_motion.gif exists but mtime check failed")
    else:
        feedback.append("FAIL: horse_motion.gif not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: GIF is Animated (15 pts)
    frames = result.get("gif_frames", 0)
    if frames > 5:
        score += 15
        feedback.append(f"GIF is animated ({frames} frames)")
    else:
        feedback.append(f"GIF is NOT animated (found {frames} frame(s))")

    # Criterion 3: GIF Width is exactly 500px (15 pts)
    width = result.get("gif_width", 0)
    if width == 500:
        score += 15
        feedback.append("GIF width is correctly 500px")
    else:
        feedback.append(f"GIF width incorrect ({width}px, expected 500px)")

    # Criterion 4: GIF Delay is 100ms (10 ImageMagick ticks) (10 pts)
    delay = result.get("gif_delay", 0)
    if delay == 10:
        score += 10
        feedback.append("GIF delay is correctly 100ms")
    else:
        feedback.append(f"GIF delay incorrect ({delay} ticks, expected 10)")

    # Criterion 5: HTML File Exists (5 pts)
    if result.get("html_exists") and result.get("html_modified"):
        score += 5
        feedback.append("cinema_history.html created")
    else:
        feedback.append("cinema_history.html missing or not modified")

    # Criterion 6: HTML embeds image (15 pts)
    if result.get("html_embeds_img"):
        score += 15
        feedback.append("HTML successfully embeds the GIF")
    else:
        feedback.append("HTML does not correctly embed horse_motion.gif")

    # Criterion 7: HTML Text content (10 pts)
    if result.get("html_has_muybridge") and result.get("html_has_1878"):
        score += 10
        feedback.append("HTML contains required keywords")
    else:
        feedback.append("HTML missing 'Muybridge' or '1878' keywords")

    # Criterion 8: HTML CSS styling (10 pts)
    if result.get("html_has_bg_color") and result.get("html_has_fg_color"):
        score += 10
        feedback.append("HTML contains required #333333 and #FFFFFF hex colors")
    else:
        feedback.append("HTML missing exact hex color codes (#333333, #FFFFFF)")

    # VLM Trajectory Verification (10 pts)
    vlm_passed = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames_to_check = sample_trajectory_frames(traj, n=4) + [get_final_screenshot(traj)]
            prompt = (
                "Review these frames from a user's session. Did the user open a web browser "
                "(like Sugar Browse) and successfully view a webpage with a dark background "
                "displaying an image of a horse? Answer ONLY 'Yes' or 'No'."
            )
            vlm_response = query_vlm(images=frames_to_check, prompt=prompt).strip().lower()
            if 'yes' in vlm_response:
                vlm_passed = True
                score += 10
                feedback.append("VLM verified HTML presentation was viewed in browser")
            else:
                feedback.append("VLM did not detect the webpage being viewed in a browser")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback.append("VLM verification skipped/failed")
    else:
        feedback.append("VLM not available")

    # Pass Threshold: >= 70 points, GIF exists, HTML embeds image
    passed = (score >= 70 and 
              result.get("gif_exists", False) and 
              result.get("html_embeds_img", False))

    if passed:
        feedback.insert(0, "SUCCESS: Animation assembled and embedded correctly!")
    else:
        feedback.insert(0, f"FAILED (Score: {score}/100)")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "gif_animated": frames > 5,
            "gif_width_correct": width == 500,
            "gif_delay_correct": delay == 10,
            "html_embeds_img": result.get("html_embeds_img", False),
            "vlm_verification": vlm_passed
        }
    }