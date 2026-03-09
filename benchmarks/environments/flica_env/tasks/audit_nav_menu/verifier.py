#!/usr/bin/env python3
"""
Verifier for audit_nav_menu task.

Scoring Criteria:
1. Output file creation and validity (10 pts)
2. Content analysis (Keywords present) (30 pts)
3. Content completeness (Item count) (20 pts)
4. Format (Clean list) (20 pts)
5. VLM Trajectory verification (Did agent actually open the menu?) (20 pts)
"""

import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, query_vlm

def verify_audit_nav_menu(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function missing"}

    metadata = task_info.get('metadata', {})
    required_items = [i.lower() for i in metadata.get('required_items', ["friends", "settings"])]
    
    score = 0
    feedback_parts = []
    max_score = 100
    
    # =========================================================
    # 1. Fetch File Metadata & Content
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Get JSON metadata
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
            
        file_exists = result_meta.get("file_exists", False)
        created_during = result_meta.get("created_during_task", False)
        
        # Get actual text content if file exists
        file_content = ""
        if file_exists:
            try:
                copy_from_env("/sdcard/menu_audit.txt", temp_txt.name)
                with open(temp_txt.name, 'r', errors='ignore') as f:
                    file_content = f.read()
            except Exception as e:
                feedback_parts.append(f"Could not read output file: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_txt.name): os.unlink(temp_txt.name)

    # =========================================================
    # 2. Score File Existence & Anti-Gaming (10 pts)
    # =========================================================
    if file_exists and created_during:
        score += 10
        feedback_parts.append("File created successfully")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but timestamp is stale (anti-gaming penalty)")
    else:
        feedback_parts.append("Output file /sdcard/menu_audit.txt not found")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback_parts)}

    # =========================================================
    # 3. Analyze Text Content (50 pts total)
    # =========================================================
    lines = [line.strip() for line in file_content.splitlines() if line.strip()]
    lower_lines = [l.lower() for l in lines]
    
    # Check for keywords (Friends, Settings) - 30 pts
    found_keywords = 0
    for keyword in required_items:
        # Loose matching: keyword must appear in some line
        if any(keyword in line for line in lower_lines):
            found_keywords += 1
            
    # Normalize keyword score (max 30)
    if len(required_items) > 0:
        keyword_score = min(30, int((found_keywords / len(required_items)) * 30))
        # Bonus: if at least "Friends" and "Settings" are found specifically
        if "friends" in lower_lines and "settings" in lower_lines:
            keyword_score = max(keyword_score, 30)
            
        score += keyword_score
        feedback_parts.append(f"Found {found_keywords}/{len(required_items)} key menu items")

    # Check Completeness/Format - 20 pts
    # Expecting a list, so line count should be substantial (>3)
    if len(lines) >= 4:
        score += 20
        feedback_parts.append(f"List contains {len(lines)} items (Good)")
    elif len(lines) > 0:
        score += 10
        feedback_parts.append(f"List too short ({len(lines)} items)")
    else:
        feedback_parts.append("File is empty")

    # =========================================================
    # 4. VLM Trajectory Verification (20 pts)
    # =========================================================
    # We need to ensure the agent actually OPENED the menu, not just guessed.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    Review this sequence of screenshots from the Flight Crew View app.
    The user is supposed to open the main navigation menu (usually a side drawer or hamburger menu).
    
    1. Do you see a navigation menu / sidebar drawer open in any of these frames?
    2. Does the menu contain items like 'Friends', 'My Schedule', or 'Settings'?
    
    Return JSON: {"menu_opened": boolean, "menu_items_visible": boolean}
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('menu_opened') or parsed.get('menu_items_visible'):
            vlm_score = 20
            feedback_parts.append("VLM confirmed menu navigation")
        else:
            feedback_parts.append("VLM did not see navigation menu open")
    else:
        # Fallback if VLM fails: give partial credit if text output is very accurate
        if score >= 50: 
            vlm_score = 10
            feedback_parts.append("VLM unavailable, partial credit")

    score += vlm_score

    # =========================================================
    # 5. Final Formatting Check (20 pts)
    # =========================================================
    # Check if lines look like menu items (short text, no weird code/JSON)
    clean_format = True
    for line in lines[:5]:
        if len(line) > 50 or "{" in line:
            clean_format = False
            break
            
    if clean_format and len(lines) > 0:
        score += 20
        feedback_parts.append("Format matches expectations")
    elif len(lines) > 0:
        score += 5
        feedback_parts.append("Format looks messy (long lines or code)")

    # Final Pass Determination
    # Must have created file + found key items + VLM/Format good enough
    passed = (score >= 60) and ("friends" in lower_lines or "settings" in lower_lines)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }