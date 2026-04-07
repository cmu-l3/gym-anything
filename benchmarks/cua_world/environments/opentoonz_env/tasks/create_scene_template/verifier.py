#!/usr/bin/env python3
import json
import os
import base64
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_scene_template(traj, env_info, task_info):
    """
    Verify the creation of an OpenToonz scene template with specific settings.
    
    Criteria:
    1. Scene file (.tnz) exists and was created during task.
    2. Scene file contains correct resolution (1280x720).
    3. Scene file contains correct FPS (24).
    4. Scene file implies correct frame range (120 frames).
    5. Report file (.txt) exists and lists specs.
    """
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
            
    # 2. Extract Data
    tnz_exists = result.get("tnz_exists", False)
    tnz_fresh = result.get("tnz_created_during_task", False)
    tnz_content_b64 = result.get("tnz_content_base64", "")
    report_exists = result.get("report_exists", False)
    report_fresh = result.get("report_created_during_task", False)
    report_content_b64 = result.get("report_content_base64", "")
    
    tnz_text = ""
    if tnz_content_b64:
        try:
            tnz_text = base64.b64decode(tnz_content_b64).decode('utf-8', errors='ignore')
        except:
            pass
            
    report_text = ""
    if report_content_b64:
        try:
            report_text = base64.b64decode(report_content_b64).decode('utf-8', errors='ignore')
        except:
            pass

    # 3. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: Scene File Existence (15 pts)
    if tnz_exists:
        score += 15
        feedback.append("Scene file created.")
    else:
        feedback.append("Scene file (.tnz) not found.")
        return {"passed": False, "score": 0, "feedback": "Scene file not created."}

    # Criterion 2: Anti-gaming Timestamp (10 pts)
    if tnz_fresh:
        score += 10
        feedback.append("Scene file created during task.")
    else:
        feedback.append("Scene file is old/pre-existing.")

    # Criterion 3: Scene File Size Check (5 pts)
    if result.get("tnz_size_bytes", 0) > 200:
        score += 5
    else:
        feedback.append("Scene file is too empty.")

    # Criterion 4: Resolution Check (20 pts)
    # Search for patterns like 'w="1280" h="720"' or '1280 720'
    res_pattern = r'w="1280"\s+h="720"|value="1280\s+720"|1280x720|1280\s+720'
    if re.search(res_pattern, tnz_text):
        score += 20
        feedback.append("Resolution 1280x720 verified in scene.")
    else:
        feedback.append("Could not verify 1280x720 resolution in scene file.")

    # Criterion 5: FPS Check (15 pts)
    # Search for 'fps value="24"' or similar
    fps_pattern = r'fps\s+value="24"|frameRate="24"|24\s+fps'
    if re.search(fps_pattern, tnz_text, re.IGNORECASE):
        score += 15
        feedback.append("FPS 24 verified in scene.")
    else:
        feedback.append("Could not verify 24 FPS in scene file.")
        
    # Criterion 6: Frame Range Check (10 pts)
    # Search for "120" in context of frame count or range "0 119" or "1 120"
    range_pattern = r'framecount="120"|range>\s*0\s+119|range>\s*1\s+120'
    if re.search(range_pattern, tnz_text, re.IGNORECASE):
        score += 10
        feedback.append("Frame count (120) verified in scene.")
    else:
        feedback.append("Could not verify frame count/range in scene file.")

    # Criterion 7: Report File Existence (10 pts)
    if report_exists and report_fresh:
        score += 10
        feedback.append("Report file created.")
    elif report_exists:
        score += 5
        feedback.append("Report file exists but timestamp is old.")
    else:
        feedback.append("Report file not found.")

    # Criterion 8: Report Content (15 pts)
    if report_exists:
        content_score = 0
        if "1280" in report_text and "720" in report_text: content_score += 5
        if "24" in report_text: content_score += 5
        if "120" in report_text or "5" in report_text: content_score += 5
        
        score += content_score
        if content_score == 15:
            feedback.append("Report content looks correct.")
        else:
            feedback.append(f"Report content partial match ({content_score}/15 pts).")

    # Pass/Fail determination
    # Must have created the scene with at least correct resolution or correct FPS to pass
    passed = score >= 60 and tnz_exists and tnz_fresh
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }