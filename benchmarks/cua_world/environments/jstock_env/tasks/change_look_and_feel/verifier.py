#!/usr/bin/env python3
"""
Verifier for change_look_and_feel task.

Criteria:
1. Programmatic: 'Nimbus' string found in JStock config file (30 pts)
2. Anti-gaming: Config file was modified DURING the task (20 pts)
3. Visual (VLM): UI appearance changed compared to initial state (25 pts)
4. Visual (VLM): UI specifically matches Nimbus style (rounded, gradient) (25 pts)

Pass threshold: 60 points (Requires at least programmatic success + valid file modification OR strong visual evidence)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_change_look_and_feel(traj, env_info, task_info):
    """
    Verify that the agent changed the JStock Look and Feel to Nimbus.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Load exported results (Programmatic Evidence)
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    nimbus_found = result.get('nimbus_config_found', False)
    config_modified = result.get('config_modified_during_task', False)
    app_running = result.get('app_was_running', False)

    # Criterion 1: Programmatic check (30 pts)
    if nimbus_found:
        score += 30
        feedback_parts.append("Config file contains 'Nimbus'")
    else:
        feedback_parts.append("Config file does NOT contain 'Nimbus'")

    # Criterion 2: Anti-gaming / Timestamp check (20 pts)
    if config_modified:
        score += 20
        feedback_parts.append("Config modified during task")
    elif nimbus_found:
        feedback_parts.append("Warning: Config has Nimbus but was NOT modified during task (pre-existing?)")
    
    # ================================================================
    # 2. VLM Verification (Visual Evidence) - 50 pts total
    # ================================================================
    # We use VLM to confirm the visual theme changed, which is the ultimate user goal.
    
    # Get frames
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        # Prompt checking for theme change and specific Nimbus characteristics
        prompt = (
            "Compare the final image to a standard desktop application. "
            "Does the application 'JStock' look like it is using the 'Nimbus' Java theme? "
            "Nimbus is characterized by:\n"
            "1. Rounded corners on buttons and text fields.\n"
            "2. Smooth gradients on buttons (often glassy/shiny).\n"
            "3. A generally more modern, softer look than the default blocky 'Metal' or 'Windows' themes.\n\n"
            "Also, look at the trajectory frames to see if the user opened the 'Look And Feel' menu.\n"
            "Answer JSON with: { 'theme_changed': boolean, 'is_nimbus': boolean, 'menu_interaction': boolean, 'reason': string }"
        )
        
        try:
            vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
            # Safe parsing
            if isinstance(vlm_response, str):
                # Try to extract JSON if wrapped in markdown code blocks
                if "