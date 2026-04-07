#!/usr/bin/env python3
"""Verifier for configure_profile_graph_overlays task.

Uses a hybrid verification strategy:
1. Programmatic: Checks if the Subsurface config file was modified during the task (+20 points)
2. VLM (Visual): Verifies the Tissue heat map overlay is visible (+35 points)
3. VLM (Visual): Verifies the Average depth overlay is visible (+35 points)
4. VLM (Trajectory): Checks for workflow progression (+10 points)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_profile_graph_overlays(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # Read Result JSON
    # ================================================================
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

    # ================================================================
    # CRITERION 1: Config file modified (Anti-gaming signal) (20 points)
    # ================================================================
    if result.get('config_modified', False):
        score += 20
        feedback_parts.append("Config file modified (+20)")
    else:
        feedback_parts.append("Config file NOT modified (Settings might have been applied dynamically)")

    # ================================================================
    # CRITERION 2-4: VLM Verification
    # ================================================================
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames

        prompt = """You are verifying if a user successfully configured the dive profile graph in Subsurface.
You are provided with several trajectory frames and the final screenshot.

Analyze the images to check the following:
1. Tissue Heat Map: Is there a colorful gradient background or band (usually transitioning from blue to green, yellow, or red) visible behind/around the main depth profile graph? This indicates nitrogen tissue loading.
2. Average Depth Line: Is there a distinct, straight, horizontal line crossing through the main dive profile, representing the mathematical average depth?
3. Workflow Progression: Did the user open the Preferences/Settings dialog or use a right-click context menu on the graph to change visualization settings?

Provide a JSON response strictly in this format:
{
  "tissue_heat_map_visible": true/false,
  "average_depth_visible": true/false,
  "workflow_progression_visible": true/false,
  "confidence": "high/medium/low",
  "reasoning": "brief explanation"
}"""

        vlm_result = query_vlm(images=images, prompt=prompt)
        parsed = vlm_result.get("parsed", {})

        # Criterion 2: Tissue Heat Map (35 pts)
        if parsed.get("tissue_heat_map_visible"):
            score += 35
            feedback_parts.append("VLM: Tissue heat map overlay visible (+35)")
        else:
            feedback_parts.append("VLM: Tissue heat map overlay NOT visible")

        # Criterion 3: Average Depth Line (35 pts)
        if parsed.get("average_depth_visible"):
            score += 35
            feedback_parts.append("VLM: Average depth line visible (+35)")
        else:
            feedback_parts.append("VLM: Average depth line NOT visible")

        # Criterion 4: Workflow Progression (10 pts)
        if parsed.get("workflow_progression_visible"):
            score += 10
            feedback_parts.append("VLM: Workflow progression verified (+10)")
        else:
            feedback_parts.append("VLM: Workflow progression NOT verified")

    except ImportError:
        feedback_parts.append("VLM module not available, visual verification skipped")
    except Exception as e:
        feedback_parts.append(f"VLM verification error: {str(e)}")

    # Check overall passage (Threshold is 70 points)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }