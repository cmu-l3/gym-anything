#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_animatic_assembly(traj, env_info, task_info):
    """
    Verify the animatic assembly task.
    
    Criteria:
    1. Output sequence exists and has ~60 frames (20 pts)
    2. Frame 10 shows Setup image (20 pts)
    3. Frame 30 shows Anticipation image (20 pts)
    4. Frame 50 shows Action image (20 pts)
    5. Timing cut (Frame 24 -> 25) is precise (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # 1. Output Existence (20 pts)
    total_frames = result.get("total_frames", 0)
    created_new = result.get("files_created_during_task", False)
    
    if total_frames >= 58 and created_new: # Allow small margin of error (e.g. 1-2 frames)
        score += 20
        feedback_parts.append(f"Sequence generated ({total_frames} frames)")
    elif total_frames > 0 and created_new:
        score += 10
        feedback_parts.append(f"Incomplete sequence ({total_frames} frames)")
    else:
        feedback_parts.append("No new output frames found")
        
    # 2. Setup Pose (20 pts)
    if result.get("frame_10_match") == "match":
        score += 20
        feedback_parts.append("Setup pose correct")
    else:
        feedback_parts.append("Setup pose incorrect/missing")

    # 3. Anticipation Pose (20 pts)
    if result.get("frame_30_match") == "match":
        score += 20
        feedback_parts.append("Anticipation pose correct")
    else:
        feedback_parts.append("Anticipation pose incorrect/missing")

    # 4. Action Pose (20 pts)
    if result.get("frame_50_match") == "match":
        score += 20
        feedback_parts.append("Action pose correct")
    else:
        feedback_parts.append("Action pose incorrect/missing")

    # 5. Timing Precision (20 pts)
    if result.get("timing_cut_accurate") is True:
        score += 20
        feedback_parts.append("Timing precision perfect (Cut at frame 25)")
    else:
        feedback_parts.append("Timing precision incorrect (Cut not at frame 24/25)")

    # Pass Threshold
    # Must get at least content right (60 pts) to pass
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }