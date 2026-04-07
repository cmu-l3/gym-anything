#!/usr/bin/env python3
"""
Verifier for DevTools Computed Style Audit.
Checks if the agent extracted the correct computed styles from the localhost page.
"""

import json
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_rgb(rgb_str):
    """Parse 'rgb(r, g, b)' into a tuple of integers."""
    if not rgb_str:
        return None
    match = re.search(r'rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)', rgb_str)
    if match:
        return tuple(map(int, match.groups()))
    return None

def color_distance(c1, c2):
    """Euclidean distance between two RGB tuples."""
    if not c1 or not c2:
        return float('inf')
    return sum((a - b) ** 2 for a, b in zip(c1, c2)) ** 0.5

def normalize_font(font_str):
    """Normalize font string (remove quotes, lowercase)."""
    if not font_str:
        return ""
    return font_str.replace('"', '').replace("'", "").lower().strip()

def verify_devtools_computed_style_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file style_audit.json not found on Desktop."}
    
    extracted = result.get('extracted_data', {})
    if not extracted:
        return {"passed": False, "score": 0, "feedback": "Output file was empty or invalid JSON."}

    # Metadata / Ground Truth
    ground_truth = task_info.get('metadata', {}).get('ground_truth', {})
    tolerances = task_info.get('metadata', {}).get('tolerances', {})
    
    score = 0
    feedback = []

    # 1. Font Family (20 pts)
    # Expected: 'DejaVu Sans' (or system specific fallback). The setup script ensures this.
    agent_font = normalize_font(extracted.get('heading_font', ''))
    expected_font = normalize_font(ground_truth.get('heading_font', 'dejavu sans'))
    
    # We allow some flexibility if it resolved to a standard Linux sans-serif
    valid_fonts = [expected_font, "liberation sans", "sans-serif"]
    
    if any(vf in agent_font for vf in valid_fonts) and agent_font != "":
        score += 20
        feedback.append("Correct Heading Font.")
    else:
        feedback.append(f"Incorrect Heading Font: Got '{agent_font}', Expected '{expected_font}'.")

    # 2. Button Color (20 pts)
    # Expected: rgb(0, 128, 255)
    agent_color_str = extracted.get('button_color', '')
    agent_color = parse_rgb(agent_color_str)
    expected_color = parse_rgb(ground_truth.get('button_color', 'rgb(0, 128, 255)'))
    
    if agent_color and color_distance(agent_color, expected_color) < tolerances.get('color_tolerance', 10):
        score += 20
        feedback.append("Correct Button Color.")
    else:
        feedback.append(f"Incorrect Button Color: Got '{agent_color_str}', Expected '{ground_truth.get('button_color')}'.")

    # 3. Alert Border Width (20 pts)
    # Expected: "6px"
    agent_border = extracted.get('alert_border_width', '').lower().strip()
    expected_border = ground_truth.get('alert_border_width', '6px')
    
    if agent_border == expected_border:
        score += 20
        feedback.append("Correct Alert Border Width.")
    elif "6" in agent_border and "px" in agent_border:
        score += 20 # Allow minor formatting diffs like "6px "
        feedback.append("Correct Alert Border Width.")
    else:
        feedback.append(f"Incorrect Alert Border Width: Got '{agent_border}', Expected '{expected_border}'.")

    # 4. Footer Opacity (20 pts)
    # Expected: "0.75"
    agent_opacity = str(extracted.get('footer_opacity', '')).strip()
    expected_opacity = ground_truth.get('footer_opacity', '0.75')
    
    if agent_opacity == expected_opacity:
        score += 20
        feedback.append("Correct Footer Opacity.")
    else:
        feedback.append(f"Incorrect Footer Opacity: Got '{agent_opacity}', Expected '{expected_opacity}'.")

    # 5. VLM / Activity Check (20 pts)
    # Did they visit the page and create the file during the task?
    if result.get('page_visited') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Activity Verified (Page Visited + File Created).")
    else:
        # Fallback to VLM if logs failed but extracted data is perfect
        if score >= 60:
             # Check if DevTools is visible in frames
             frames = sample_trajectory_frames(traj, n=3)
             final_ss = get_final_screenshot(traj)
             images = frames + ([final_ss] if final_ss else [])
             
             try:
                 vlm_res = query_vlm(images, "Is the browser Developer Tools (Inspect Element panel) visible in any of these images? Answer yes or no.")
                 if "yes" in vlm_res.get('response', '').lower():
                     score += 20
                     feedback.append("VLM confirmed DevTools usage.")
                 else:
                     feedback.append("Could not verify DevTools usage via logs or VLM.")
             except:
                 pass

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }