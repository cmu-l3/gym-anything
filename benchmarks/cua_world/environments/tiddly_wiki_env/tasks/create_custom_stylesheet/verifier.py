#!/usr/bin/env python3
"""
Verifier for create_custom_stylesheet task.

Checks both programmatic evidence (files, API, tags, content) 
and VLM evidence (trajectory of actions, dark theme visible).
"""

import json
import os
import tempfile
import logging
import sys

# Add VLM utilities path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("VLM utilities not available. VLM checks will be skipped.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's task to apply a custom dark theme to a TiddlyWiki interface.

Review the trajectory frames (showing progression) and the final screenshot.
1. WORKFLOW: Did the agent create a new tiddler, enter CSS text, set tags/types, and save?
2. VISUAL_RESULT: Does the final screenshot show the TiddlyWiki UI transformed into a dark theme? 
   (Specifically, look for a dark blue-black background with light text, and lavender/blue accents).

Respond in JSON format:
{
    "workflow_observed": true/false,
    "dark_theme_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_create_custom_stylesheet(traj, env_info, task_info):
    """
    Verify that the stylesheet tiddler was created and the theme was applied.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read Programmatic Result JSON
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

    # 2. Evaluate Programmatic Criteria (70 points total)
    
    # Tiddler exists (10 pts)
    if result.get('tiddler_exists', False):
        score += 10
        feedback_parts.append("Tiddler exists")
        
        # Anti-gaming: Created during task (10 pts)
        if result.get('created_during_task', False):
            score += 10
            feedback_parts.append("Created during task")
        else:
            feedback_parts.append("Warning: Tiddler existed before task start")
    else:
        feedback_parts.append("FAIL: Tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Correct Tag (15 pts)
    if result.get('has_stylesheet_tag', False):
        score += 15
        feedback_parts.append("Correct tag applied")
    else:
        feedback_parts.append("FAIL: Missing $:/tags/Stylesheet tag")

    # Correct Type (10 pts)
    if result.get('has_css_type', False):
        score += 10
        feedback_parts.append("Correct type applied")
    else:
        feedback_parts.append("FAIL: Missing text/css type")

    # Colors Found (15 pts max, 3 pts per color)
    colors_count = result.get('colors_found_count', 0)
    color_score = min(15, colors_count * 3)
    score += color_score
    feedback_parts.append(f"Found {colors_count}/5 target CSS colors")

    # API Accessibility (10 pts)
    if result.get('api_status') == "200":
        score += 10
        feedback_parts.append("Tiddler accessible via API")
    else:
        feedback_parts.append("API request failed")

    # 3. Evaluate VLM Criteria (30 points total)
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if final_img:
            images = frames + [final_img] if frames else [final_img]
            
            try:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    if parsed.get("workflow_observed", False):
                        score += 10
                        feedback_parts.append("VLM: Workflow progression observed")
                    else:
                        feedback_parts.append("VLM: Workflow not clearly observed")
                        
                    if parsed.get("dark_theme_visible", False):
                        score += 20
                        feedback_parts.append("VLM: Dark theme is visible in UI")
                    else:
                        feedback_parts.append("VLM: Dark theme NOT visible in UI")
                else:
                    feedback_parts.append(f"VLM verification failed: {vlm_result.get('error')}")
            except Exception as e:
                feedback_parts.append(f"VLM exception: {str(e)}")
    else:
        feedback_parts.append("VLM skipped (not available or missing trajectory)")

    # 4. Final Assessment
    # Key criteria: Tiddler must exist, must have the tag, and must have at least some CSS
    key_criteria_met = (
        result.get('tiddler_exists', False) and 
        result.get('has_stylesheet_tag', False) and 
        colors_count >= 2
    )
    
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }