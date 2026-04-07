#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_filtered_dashboard(traj, env_info, task_info):
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
    feedback = []

    # 1. Tiddler exists and timestamp anti-gaming check
    if result.get("exists"):
        mtime = result.get("mtime", 0)
        start_time = result.get("start_time", 0)
        if mtime >= start_time:
            score += 15
            feedback.append("Tiddler exists and was created/modified during task.")
        else:
            feedback.append("Tiddler exists but timestamp predates task start (Possible cheating).")
    else:
        feedback.append("Project Dashboard tiddler not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    body = result.get("body", "")
    
    # Check body length
    if len(body) < 50:
        feedback.append("Body too short. The dashboard is missing required components.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Check for List widget usage
    if "<$list" in body:
        score += 10
        feedback.append("Found <$list> widget.")
    else:
        feedback.append("Missing <$list> widget.")

    # 3. Check for specific status filters (Todo, InProgress, Done)
    filters_found = 0
    if re.search(r"tag\[Todo\]", body, re.IGNORECASE):
        filters_found += 1
        score += 10
    if re.search(r"tag\[InProgress\]", body, re.IGNORECASE):
        filters_found += 1
        score += 10
    if re.search(r"tag\[Done\]", body, re.IGNORECASE):
        filters_found += 1
        score += 10
    feedback.append(f"Found {filters_found}/3 required tag filters.")

    # 4. Check for Count widget usage
    if "<$count" in body:
        score += 10
        feedback.append("Found <$count> widget.")
    else:
        feedback.append("Missing <$count> widget.")

    # 5. Check for distinct section headings
    heading_count = len(re.findall(r"^!+\s*\w+", body, re.MULTILINE))
    if heading_count >= 2:
        score += 5
        feedback.append("Found section headings.")
    else:
        feedback.append("Missing or insufficient section headings.")

    # 6. Check Dashboard tag applied to the tiddler itself
    if "Dashboard" in result.get("tags", ""):
        score += 5
        feedback.append("Dashboard tag applied.")
    else:
        feedback.append("Dashboard tag missing.")

    # 7. Anti-gaming: Ensure tasks are populated by filter, not hardcoded
    hardcoded = result.get("hardcoded_titles", 0)
    if hardcoded > 3:
        score -= 30
        feedback.append(f"PENALTY: Found {hardcoded} hardcoded task titles instead of dynamic rendering.")

    # 8. VLM Verification (Trajectory & Layout Analysis)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """
        You are verifying if the agent successfully created a "Project Dashboard" in TiddlyWiki.
        
        Check the provided trajectory frames and final screenshot:
        1. Did the agent navigate the TiddlyWiki interface and type within a tiddler editor?
        2. In the final rendering, are there distinct sections (e.g. Todo, InProgress, Done) showing lists of tasks?
        3. Do the lists appear to be dynamically rendered (showing multiple items correctly as clickable links)?
        
        Return JSON format:
        {
          "used_ui": true/false,
          "sections_rendered": true/false,
          "dynamic_lists_visible": true/false
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, images=images)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("used_ui"): vlm_score += 5
            if parsed.get("sections_rendered"): vlm_score += 10
            if parsed.get("dynamic_lists_visible"): vlm_score += 10
            feedback.append(f"VLM Verification: +{vlm_score} pts.")
        else:
            feedback.append("VLM Verification failed or unavailable.")
    except Exception as e:
        feedback.append(f"VLM Exception: {str(e)}")
    
    score += vlm_score
    score = max(0, min(100, score))
    
    # Must have used lists and filters properly to pass
    key_criteria_met = (filters_found >= 2) and ("<$list" in body)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }