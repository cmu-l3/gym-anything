#!/usr/bin/env python3
"""
Verifier for vse_rough_cut_assembly task.

Verifies:
1. 3+ Movie strips imported (20 pts)
2. Strips arranged sequentially (15 pts)
3. Transitions added (20 pts)
4. Text title added (15 pts)
5. Rendered video output valid (20 pts)
6. Blend file saved (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vse_rough_cut_assembly(traj, env_info, task_info):
    """
    Verify VSE rough cut assembly task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_text_keywords = metadata.get('required_text', ["bmw", "showcase"])

    # Load result
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
    
    task_start = result.get("task_start", 0)
    blend_info = result.get("blend_file", {})
    render_info = result.get("render_output", {})
    vse_data = result.get("vse_data", {})
    
    # Check Anti-Gaming (File timestamps)
    blend_new = blend_info.get("mtime", 0) > task_start
    render_new = render_info.get("mtime", 0) > task_start
    
    if not blend_new and not render_new:
         return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new files created during task session."
        }

    # 1. Check Movie Strips (20 pts)
    movie_strips = vse_data.get("movie_strips", [])
    if len(movie_strips) >= 3:
        score += 20
        feedback_parts.append("3+ movie strips imported")
    elif len(movie_strips) > 0:
        score += 10
        feedback_parts.append(f"Only {len(movie_strips)} movie strips found (need 3)")
    else:
        feedback_parts.append("No movie strips found")

    # 2. Check Sequencing (15 pts)
    # Strips are already sorted by start_frame in export script
    is_sequential = False
    if len(movie_strips) >= 2:
        is_sequential = True
        for i in range(len(movie_strips) - 1):
            curr_start = movie_strips[i]["start_frame"]
            next_start = movie_strips[i+1]["start_frame"]
            # Next strip should start after current starts (allow overlaps for transitions)
            if next_start <= curr_start: 
                is_sequential = False
                break
    
    if is_sequential:
        score += 15
        feedback_parts.append("Clips arranged sequentially")
    elif len(movie_strips) >= 2:
        feedback_parts.append("Clips not arranged sequentially")

    # 3. Check Transitions (20 pts)
    transitions = vse_data.get("transition_strips", [])
    if len(transitions) >= 1:
        score += 20
        feedback_parts.append(f"{len(transitions)} transition(s) found")
    else:
        feedback_parts.append("No transition effects found")

    # 4. Check Text Title (15 pts)
    text_strips = vse_data.get("text_strips", [])
    found_text = False
    for ts in text_strips:
        content = ts.get("text", "").lower()
        # check if ANY keyword is present
        if any(kw in content for kw in required_text_keywords):
            found_text = True
            break
            
    if found_text:
        score += 15
        feedback_parts.append("Title text found")
    elif len(text_strips) > 0:
        score += 5
        feedback_parts.append("Text strip found but missing keywords")
    else:
        feedback_parts.append("No text title found")

    # 5. Check Rendered Output (20 pts)
    if render_info.get("valid", False) and render_new:
        score += 20
        feedback_parts.append("Valid video rendered")
    elif render_info.get("exists", False):
        score += 5
        feedback_parts.append("Video file exists but invalid/empty")
    else:
        feedback_parts.append("No rendered video output")

    # 6. Check Blend File Saved (10 pts)
    if blend_info.get("valid", False) and blend_new:
        score += 10
        feedback_parts.append("Project saved")
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }