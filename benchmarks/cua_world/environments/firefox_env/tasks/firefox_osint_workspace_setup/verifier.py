#!/usr/bin/env python3
"""
Verifier for firefox_osint_workspace_setup task.

Verification Strategy:
1. Filesystem: Checks if Evidence directory and screenshot were created.
2. Prefs.js: Checks if Strict tracking protection and default download directory were set.
3. SQLite DB: Queries Firefox bookmarks to confirm OSINT reference is pinned to the toolbar.
4. VLM (Hybrid): Uses trajectory and final screenshots to visually verify Dark theme, 
   toolbar presence, and organic GUI interaction.
"""

import json
import tempfile
import os
import logging
import re

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_osint_setup(traj, env_info, task_info):
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

    # 1. Evidence Directory (10 pts)
    if result.get('evidence_dir_exists'):
        score += 10
        feedback_parts.append("Evidence dir exists")
    else:
        feedback_parts.append("Evidence dir missing")

    # 2. Agent Screenshot (10 pts)
    if result.get('agent_screenshot_exists'):
        score += 10
        feedback_parts.append("Agent screenshot created")
    else:
        feedback_parts.append("Agent screenshot missing")

    # 3. Download Path Preference (15 pts)
    download_dir = result.get('download_dir', '')
    if 'OSINT_Evidence' in download_dir:
        score += 15
        feedback_parts.append("Download path correctly updated")
    else:
        feedback_parts.append(f"Download path incorrect or unset")

    # 4. Strict Tracking Protection (15 pts)
    if result.get('strict_tracking'):
        score += 15
        feedback_parts.append("Strict tracking verified via prefs")
    else:
        feedback_parts.append("Strict tracking not enabled")

    # 5. SQLite Bookmark DB Analysis (20 pts)
    try:
        toolbar_count = int(result.get('toolbar_bookmark_count', 0))
        bookmark_count = int(result.get('bookmark_count', 0))
    except ValueError:
        toolbar_count, bookmark_count = 0, 0
    
    if toolbar_count > 0:
        score += 20
        feedback_parts.append("Reference pinned to Bookmarks Toolbar (DB confirmed)")
    elif bookmark_count > 0:
        score += 10
        feedback_parts.append("Reference bookmarked, but not in Toolbar")
    else:
        feedback_parts.append("Reference not bookmarked")

    # 6. VLM Trajectory & Final View Verification (30 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images_to_check = []
    
    if frames:
        images_to_check.extend(frames)
    if final:
        images_to_check.append(final)
        
    if images_to_check:
        prompt = """You are evaluating an agent's execution of a Firefox configuration task.
Please determine if the following criteria are met based on the trajectory and final screenshots:
1. Is the Firefox Dark theme active in the final screenshot?
2. Is the Bookmarks Toolbar physically rendered on the screen (below the URL bar)?
3. Did the agent interact with the Settings/Preferences GUI during the trajectory?

Respond EXACTLY with valid JSON in this format:
{
    "dark_theme_active": true/false,
    "bookmarks_toolbar_visible": true/false,
    "gui_interaction_visible": true/false
}
"""
        try:
            vlm_res = query_vlm(images=images_to_check, prompt=prompt)
            text = vlm_res if isinstance(vlm_res, str) else vlm_res.get('text', '')
            
            # Extract JSON block
            json_match = re.search(r'\{[^{}]*\}', text, re.DOTALL)
            parsed = {}
            if json_match:
                try:
                    parsed = json.loads(json_match.group(0))
                except json.JSONDecodeError:
                    pass
            
            # Robust extraction fallback
            if not parsed:
                text_lower = text.lower()
                parsed = {
                    "dark_theme_active": "true" in text_lower and "dark" in text_lower,
                    "bookmarks_toolbar_visible": "true" in text_lower and "toolbar" in text_lower,
                    "gui_interaction_visible": "true" in text_lower and "gui" in text_lower
                }
            
            if parsed.get("dark_theme_active", False):
                score += 5
                feedback_parts.append("VLM: Dark theme visible")
                
            if parsed.get("bookmarks_toolbar_visible", False):
                score += 10
                feedback_parts.append("VLM: Toolbar visible")
                
            if parsed.get("gui_interaction_visible", False):
                score += 15
                feedback_parts.append("VLM: GUI interaction verified")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification failed")
            # Grant fallback points if we confidently know UI manipulation happened via DB state
            if toolbar_count > 0:
                score += 15

    # Pass Threshold Logic: Must score >= 70 AND have manipulated the DB (proves it didn't just write scripts)
    db_manipulated = toolbar_count > 0 or bookmark_count > 0
    passed = score >= 70 and db_manipulated
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }