#!/usr/bin/env python3
"""Verifier for offline_wildlife_gallery_html task.

Checks that the agent processed high-resolution images into <=200px thumbnails
using bash/tools, and structured an HTML file connecting them accurately to the
original high-resolution image paths.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_offline_wildlife_gallery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check HTML Creation & Anti-gaming (10 points)
    if result.get("html_exists"):
        if result.get("html_modified"):
            score += 10
            feedback_parts.append("index.html created/modified")
        else:
            score += 5
            feedback_parts.append("index.html exists but mtime check failed (pre-existing)")
    else:
        feedback_parts.append("FAIL: index.html missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check HTML Heading presence (10 points)
    if result.get("heading_found"):
        score += 10
        feedback_parts.append("Heading 'Wildlife Gallery' found")
    else:
        feedback_parts.append("Heading 'Wildlife Gallery' missing")

    # 3. Check Thumbnail batch processing execution (15 points)
    thumb_count = result.get("thumb_count", 0)
    if thumb_count == 3:
        score += 15
        feedback_parts.append("3 thumbnails created")
    else:
        score += thumb_count * 5
        feedback_parts.append(f"{thumb_count}/3 thumbnails created")

    # 4. Check Thumbnail exact dimensions constraints (15 points)
    thumbs_valid_size = result.get("thumbs_valid_size", False)
    if thumbs_valid_size and thumb_count > 0:
        score += 15
        feedback_parts.append("Thumbnails <= 200x200 pixels")
    else:
        feedback_parts.append("Thumbnails missing or exceed 200x200 pixels")

    expected_files = ["monarch_butterfly.jpg", "red_eyed_tree_frog.jpg", "galapagos_tortoise.jpg"]

    # 5. Check semantic structural connection: `<img>` tags (15 points)
    img_tags = result.get("img_tags", [])
    img_matches = sum(1 for expected in expected_files if any(expected in src for src in img_tags))
    if img_matches == 3:
        score += 15
        feedback_parts.append("3 valid <img> tags found")
    else:
        score += int((img_matches / 3.0) * 15)
        feedback_parts.append(f"{img_matches}/3 valid <img> tags found")

    # 6. Check structural functionality: `<a>` tags pointing to originals (20 points)
    a_tags = result.get("a_tags", [])
    a_matches = sum(1 for expected in expected_files if any(expected in href for href in a_tags))
    if a_matches == 3:
        score += 20
        feedback_parts.append("3 valid <a> link tags found")
    else:
        score += int((a_matches / 3.0) * 20)
        feedback_parts.append(f"{a_matches}/3 valid <a> link tags found")

    # 7. VLM check for Terminal/Code usage trajectory (15 points)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = (
            "Review the provided screenshots of the user's trajectory. "
            "Did the user use the Terminal, command line interface, or a text/code editor (like Nano, Vi, or Pippy) "
            "to process the images and write HTML code? "
            "Reply with 'YES' if there is evidence of Terminal/editor usage, or 'NO' if not."
        )
        vlm_response = query_vlm(images=images, prompt=prompt)
        
        if "yes" in vlm_response.lower():
            vlm_score = 15
            feedback_parts.append("VLM verified Terminal/Editor usage")
        else:
            feedback_parts.append("VLM found no evidence of Terminal/Editor usage")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Soft pass: waive points heavily depending on VLM, partial if unavailable
        vlm_score = 10
        feedback_parts.append("VLM check bypassed (error)")

    score += vlm_score

    # Final Pass Condition
    # Agent must earn >=70 points, correctly size the thumbs, and have at least 2 img + link structures.
    passed = (
        score >= 70 and 
        thumbs_valid_size and 
        img_matches >= 2 and 
        a_matches >= 2
    )

    if passed:
        feedback_parts.append("SUCCESS: Offline gallery task complete")
    else:
        feedback_parts.append("FAILED: Did not meet all required functional HTML/sizing criteria")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }