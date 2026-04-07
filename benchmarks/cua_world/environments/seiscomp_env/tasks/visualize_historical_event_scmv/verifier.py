#!/usr/bin/env python3
"""
Verifier for visualize_historical_event_scmv task.

Verification Strategy:
1. Parse configuration output to verify `visibleTimeSpan` >= 1000 days (30 pts).
2. Parse configuration output to verify `retention` >= 1000 days (20 pts).
3. Validate presence of saved screenshot ensuring it was created during task (20 pts).
4. Run VLM checks on trajectory frames to visually verify the config workflow & final map event symbol (30 pts).

Pass threshold is 70 points AND key criteria met.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_time_span(time_str: str) -> float:
    """Parse SeisComP time span string into seconds."""
    if not time_str:
        return 0.0
    time_str = time_str.strip().lower()
    try:
        if time_str.endswith('d'):
            return float(time_str[:-1]) * 86400
        elif time_str.endswith('h'):
            return float(time_str[:-1]) * 3600
        elif time_str.endswith('m'):
            return float(time_str[:-1]) * 60
        elif time_str.endswith('s'):
            return float(time_str[:-1])
        else:
            return float(time_str)
    except ValueError:
        return 0.0

def verify_visualize_historical_event_scmv(traj, env_info, task_info):
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

    score = 0
    feedback_parts = []
    
    # 1. Config parameters checks
    visible_span = parse_time_span(result.get("visible_time_span", ""))
    retention = parse_time_span(result.get("retention", ""))
    
    # Target is > 1000 days -> 86400000 seconds
    if visible_span >= 86400000:
        score += 30
        feedback_parts.append(f"events.visibleTimeSpan is correctly set to >= 1000 days ({visible_span}s)")
    elif visible_span > 0:
        score += 10
        feedback_parts.append(f"events.visibleTimeSpan was increased but is too short ({visible_span}s)")
    else:
        feedback_parts.append("events.visibleTimeSpan not correctly set")

    if retention >= 86400000:
        score += 20
        feedback_parts.append(f"events.retention is correctly set to >= 1000 days ({retention}s)")
    elif retention > 0:
        score += 5
        feedback_parts.append(f"events.retention was increased but is too short ({retention}s)")
    else:
        feedback_parts.append("events.retention not correctly set")
        
    # 2. Screenshot file checks
    screenshot_exists = result.get("screenshot_exists", False)
    screenshot_created = result.get("screenshot_created_during_task", False)
    
    if screenshot_exists and screenshot_created:
        score += 20
        feedback_parts.append("Screenshot file correctly created")
    else:
        feedback_parts.append("Screenshot file missing or not created during task")

    # 3. VLM Trajectory Verification
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            prompt = """You are analyzing a sequence of screenshots from an agent configuring and using SeisComP Map View (scmv).

The screenshots show the progression of the task over time.
Determine if the following criteria are met:
1. WORKFLOW_OBSERVED: Did the agent configure the application (e.g., editing a config file in terminal or a text editor) and then open the scmv map application?
2. SCMV_VISIBLE: Is the scmv application visible in the later frames?
3. EVENT_SYMBOL: In the map view (which should be zoomed in/centered near Japan), is there an earthquake symbol (colored circle/star) clearly visible indicating the historical event?

Respond in JSON format:
{
    "workflow_observed": true/false,
    "scmv_visible": true/false,
    "event_symbol_visible": true/false,
    "reasoning": "your explanation of the progression"
}"""
            
            vlm_res = query_vlm(prompt=prompt, images=frames + [final])
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("workflow_observed"):
                    score += 10
                    feedback_parts.append("VLM: Configuration workflow observed")
                else:
                    feedback_parts.append("VLM: Configuration workflow NOT clearly observed")
                    
                if parsed.get("scmv_visible") and parsed.get("event_symbol_visible"):
                    score += 20
                    feedback_parts.append("VLM: Map shows Japan with earthquake symbol")
                else:
                    feedback_parts.append("VLM: Event symbol on map NOT clearly visible")
            else:
                feedback_parts.append("VLM verification failed")
                
        except Exception as e:
            feedback_parts.append(f"Failed to run VLM trajectory check: {e}")
    else:
        feedback_parts.append("VLM unavailable - skipping visual check")

    # 4. Final Verification
    key_criteria = (visible_span >= 86400000) and screenshot_exists
    passed = score >= 70 and key_criteria

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }