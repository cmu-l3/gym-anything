#!/usr/bin/env python3
"""
Verifier for Corporate Signage Overlay Deployment task.

VERIFICATION STRATEGY:
1. Script Exists & Executable: Check file flags.
2. Script Contents - Playback: Regex for looping and fullscreen VLC arguments.
3. Script Contents - Logo: Regex for logo file path, filter chain, and top-left placement.
4. Script Contents - Marquee: Regex for text file, color (Hex/Dec), and bottom placement.
5. Proof Image - Existence & CV2: Verify image exists, use OpenCV to detect yellow pixels at the bottom.
6. Proof Image - VLM: Use VLM on trajectory to confirm visual rendering of the overlays.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_corporate_signage_overlay_deployment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON results
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

    script_exists = result.get('script_exists', False)
    script_executable = result.get('script_executable', False)
    script_contents = result.get('script_contents', '')
    screenshot_exists = result.get('screenshot_exists', False)

    # 1. Script Exists & Executable (10 pts)
    if script_exists:
        if script_executable:
            score += 10
            feedback_parts.append("+ Script exists and is executable")
        else:
            score += 5
            feedback_parts.append("~ Script exists but is NOT executable")
    else:
        feedback_parts.append("x Script launch_signage.sh does not exist")
        # Critical failure, no script
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Playback flags (15 pts)
    has_loop = re.search(r'(--loop|-L)', script_contents)
    has_fullscreen = re.search(r'(--fullscreen|-f|cvlc)', script_contents)
    
    if has_loop and has_fullscreen:
        score += 15
        feedback_parts.append("+ Looping and fullscreen flags found")
    else:
        if has_loop:
            score += 7
            feedback_parts.append("~ Looping flag found, but missing fullscreen")
        elif has_fullscreen:
            score += 7
            feedback_parts.append("~ Fullscreen flag found, but missing loop")
        else:
            feedback_parts.append("x Missing loop and fullscreen flags")

    # 3. Logo Configuration (20 pts)
    has_logo = 'logo' in script_contents and 'corp_logo.png' in script_contents
    # VLC position 5 is top-left, or explicit coordinates
    has_logo_pos = re.search(r'logo-position=5|logo-x=0', script_contents)
    
    if has_logo:
        score += 10
        if has_logo_pos:
            score += 10
            feedback_parts.append("+ Logo config complete (path and top-left pos)")
        else:
            feedback_parts.append("~ Logo config found but missing explicit top-left position")
    else:
        feedback_parts.append("x Logo configuration missing")

    # 4. Marquee Configuration (20 pts)
    has_marq = 'marq' in script_contents and ('ticker_text.txt' in script_contents or 'Global Tech Summit' in script_contents)
    has_marq_color = re.search(r'16776960|FFFF00', script_contents, re.IGNORECASE)
    has_marq_pos = re.search(r'marq-position=8', script_contents)  # 8 is bottom
    
    if has_marq:
        score += 10
        if has_marq_color and has_marq_pos:
            score += 10
            feedback_parts.append("+ Marquee config complete (text, color, bottom pos)")
        elif has_marq_color:
            score += 5
            feedback_parts.append("~ Marquee config found with color but missing explicit bottom pos")
        else:
            feedback_parts.append("~ Marquee config found but missing exact color/position mapping")
    else:
        feedback_parts.append("x Marquee configuration missing")

    # 5 & 6. Proof Image Validation (CV2 + VLM) (35 pts total)
    if screenshot_exists:
        score += 10
        feedback_parts.append("+ Proof screenshot generated")

        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/signage_proof.png", temp_img.name)
            
            # OpenCV validation for Yellow Text at the Bottom
            try:
                import cv2
                import numpy as np
                img = cv2.imread(temp_img.name)
                if img is not None:
                    h, w = img.shape[:2]
                    # Check bottom 25% of image
                    bottom_roi = img[int(h*0.75):, :]
                    hsv = cv2.cvtColor(bottom_roi, cv2.COLOR_BGR2HSV)
                    # Yellow in OpenCV HSV: H is ~20-40
                    lower_yellow = np.array([15, 100, 100])
                    upper_yellow = np.array([45, 255, 255])
                    mask = cv2.inRange(hsv, lower_yellow, upper_yellow)
                    yellow_pixels = cv2.countNonZero(mask)
                    
                    if yellow_pixels > 50:
                        score += 15
                        feedback_parts.append(f"+ CV2: Yellow text detected at bottom ({yellow_pixels} px)")
                    else:
                        feedback_parts.append(f"x CV2: Yellow text NOT detected at bottom ({yellow_pixels} px)")
                else:
                    feedback_parts.append("x CV2: Failed to read screenshot image")
            except ImportError:
                logger.warning("OpenCV not installed, skipping color detection.")
                feedback_parts.append("~ CV2: Skipped (Not Installed)")
            except Exception as e:
                logger.error(f"CV2 validation error: {e}")
                feedback_parts.append(f"x CV2 validation error: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

        # VLM validation using Trajectory + Final Proof
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            frames.append(get_final_screenshot(traj))
            
            prompt = """You are an AV engineer verifying a digital signage deployment task.
            Check these trajectory frames to confirm:
            1. Did the agent write and execute a VLC script?
            2. Is there a fullscreen video playing?
            3. Is there a company logo visibly overlaid in the TOP-LEFT corner of the video?
            4. Is there YELLOW scrolling text visibly overlaid at the BOTTOM of the video?
            
            Provide your response strictly in the following JSON format:
            {"script_executed": true/false, "fullscreen_video": true/false, "logo_top_left": true/false, "yellow_text_bottom": true/false}
            """
            try:
                result = query_vlm(prompt=prompt, images=frames)
                if result and result.get("success") and result.get("parsed"):
                    parsed = result["parsed"]
                    if parsed.get("logo_top_left") and parsed.get("yellow_text_bottom"):
                        score += 10
                        feedback_parts.append("+ VLM: Confirmed visual overlay placement")
                    else:
                        feedback_parts.append("~ VLM: Overlays not clearly visible in expected positions")
                else:
                    feedback_parts.append("~ VLM: Validation failed to parse")
            except Exception as e:
                logger.error(f"VLM verification error: {e}")
                feedback_parts.append("~ VLM: Exception during query")
    else:
        feedback_parts.append("x Proof screenshot missing")

    # Final logic
    passed = score >= 75
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}