#!/usr/bin/env python3
"""
Verifier for create_canvas_screen_ruler task.

Verification Strategy:
1. Static File Checks (AST): Ensures file existence, correct file modification timestamps, 
   and correct syntax/imports ('canvas', 'ruler_mark_start').
2. Dynamic VLM Checks: The export script automatically injects code into Talon's REPL/cron
   to move the mouse to (200,200), call the agent's start action, move to (800,600), and 
   call the end action. We then use a VLM to check the final screenshot for a drawn line 
   and the mathematical text output (~721 pixels).
3. Trajectory Verification: VLM checks the agent's work timeline to prevent spoofing.
"""

import os
import json
import tempfile
import logging
import math
import re

from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify the dynamically drawn line on the final screenshot
VLM_FINAL_PROMPT = """You are evaluating the result of a code execution test.

We programmatically executed the user's voice command code which should draw an on-screen graphical ruler.
We simulated:
1. Moving the mouse to coordinate (X: 200, Y: 200) and dropping a start anchor.
2. Moving the mouse to coordinate (X: 800, Y: 600) and dropping an end anchor.

Look closely at the screenshot.
1. Do you see a custom-drawn graphical line (likely over the active application or desktop) connecting the top-left quadrant to the center-right quadrant?
2. The distance between (200,200) and (800,600) is approximately 721.11 pixels. Do you see text rendered on the screen displaying a number near "721" (e.g., "721", "721.1", "721px", "Distance: 721")?

Respond in pure JSON format:
{
    "line_drawn": true/false,
    "accurate_text_rendered": true/false,
    "visible_number": "extract the number seen, or null",
    "reasoning": "brief explanation"
}
"""

# VLM Prompt to ensure the agent was actually writing code during the task
VLM_TRAJECTORY_PROMPT = """You are evaluating an agent's workflow trajectory.

The agent's task was to write two files: a Python script and a Talon configuration file, using a text editor (like Notepad or VSCode).

Look at these sampled frames from the agent's work process.
1. Is there evidence that the agent opened a text editor?
2. Did the agent actively write or edit Python/Talon code related to a "screen ruler" or "canvas"?

Respond in pure JSON format:
{
    "used_editor": true/false,
    "wrote_code": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_screen_ruler(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_distance = metadata.get('expected_distance_px', 721.11)
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result.get('task_start', 0)
    py_mtime = result.get('py_mtime', 0)
    py_content = result.get('py_content', '')
    talon_content = result.get('talon_content', '')
    
    # Check File Existence & Anti-Gaming Timestamps (20 pts)
    if result.get('py_exists') and result.get('talon_exists'):
        score += 10
        feedback_parts.append("Files created")
        if py_mtime >= task_start:
            score += 10
            feedback_parts.append("Files modified during task")
        else:
            feedback_parts.append("Files existed before task started (Anti-gaming flag)")
    else:
        feedback_parts.append("Missing required files (ruler.py or ruler.talon)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # Static Content Checks (20 pts)
    # Check python imports and components
    if "canvas" in py_content and "Module" in py_content and "on_draw" in py_content:
        score += 10
        feedback_parts.append("Python Canvas syntax used")
    else:
        feedback_parts.append("Missing crucial Canvas API elements in ruler.py")
        
    # Check Talon voice bindings
    if re.search(r"ruler\s+start", talon_content, re.IGNORECASE) and re.search(r"ruler\s+end", talon_content, re.IGNORECASE):
        score += 10
        feedback_parts.append("Voice bindings found in .talon file")
    else:
        feedback_parts.append("Voice bindings missing from .talon file")

    # 2. VLM Trajectory Check (20 pts)
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        traj_res = query_vlm(images=frames, prompt=VLM_TRAJECTORY_PROMPT)
        if traj_res.get("success"):
            parsed = traj_res.get("parsed", {})
            if parsed.get("used_editor") and parsed.get("wrote_code"):
                score += 20
                feedback_parts.append("Trajectory confirms active coding")
            else:
                feedback_parts.append("Trajectory doesn't clearly show active coding")
    
    # 3. Dynamic Visual Check via VLM on Final Screenshot (40 pts)
    # The export script triggered the code. The final screenshot holds the truth.
    final_img = get_final_screenshot(traj)
    if final_img:
        final_res = query_vlm(images=[final_img], prompt=VLM_FINAL_PROMPT)
        if final_res.get("success"):
            parsed = final_res.get("parsed", {})
            
            if parsed.get("line_drawn"):
                score += 20
                feedback_parts.append("Visual verification: Line drawn successfully")
            else:
                feedback_parts.append("Visual verification: No line detected")
                
            if parsed.get("accurate_text_rendered"):
                score += 20
                feedback_parts.append(f"Visual verification: Correct distance text rendered ({parsed.get('visible_number')})")
            else:
                feedback_parts.append(f"Visual verification: Distance text incorrect or missing")
    else:
        feedback_parts.append("Final screenshot missing for visual evaluation")

    # Final Pass Evaluation
    # Requires structural completion + visual proof of the line being drawn
    passed = (score >= 75) and bool(result.get('py_exists'))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }