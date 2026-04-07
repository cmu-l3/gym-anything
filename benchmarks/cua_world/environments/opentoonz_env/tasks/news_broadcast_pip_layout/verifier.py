#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_news_broadcast_pip_layout(traj, env_info, task_info):
    """
    Verifies that the agent created a PiP broadcast layout correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Output Files Created (10 pts)
    if result.get("files_created_during_task", False):
        score += 10
        feedback_parts.append("New output files created")
    else:
        feedback_parts.append("No new output files found")

    # 2. Frame Count (10 pts)
    count = result.get("frame_count", 0)
    if count >= 24:
        score += 10
        feedback_parts.append(f"Frame count OK ({count})")
    elif count > 0:
        score += 5
        feedback_parts.append(f"Frame count low ({count}/24)")
        
    # 3. Resolution (20 pts)
    dims = result.get("resolution", [0, 0])
    if dims == [1920, 1080]:
        score += 20
        feedback_parts.append("Resolution 1920x1080 OK")
    else:
        feedback_parts.append(f"Incorrect resolution: {dims}")
        
    # 4. Background Visibility - BL Quadrant (30 pts)
    # Match score is 0.0 to 1.0 (1.0 = perfect match to bg image)
    bl_match = result.get("bl_quadrant_match", 0.0)
    if bl_match > 0.85:
        score += 30
        feedback_parts.append("Background visible in bottom-left")
    elif bl_match > 0.5:
        score += 15
        feedback_parts.append("Background partially matching in bottom-left")
    else:
        feedback_parts.append(f"Bottom-left quadrant mismatch (score {bl_match:.2f}) - did you overlay the background?")

    # 5. Animation Presence - TR Quadrant (20 pts)
    # Activity score > 0.0 means pixel diff from clean BG
    tr_activity = result.get("tr_quadrant_activity", 0.0)
    if tr_activity > 0.1:
        score += 20
        feedback_parts.append("Animation overlay detected in top-right")
    else:
        feedback_parts.append("Top-right quadrant looks exactly like background - missing animation?")

    # 6. Motion Check (10 pts)
    tr_motion = result.get("tr_motion_score", 0.0)
    if tr_motion > 0.05:
        score += 10
        feedback_parts.append("Animation motion detected")
    else:
        feedback_parts.append("Top-right quadrant appears static")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }