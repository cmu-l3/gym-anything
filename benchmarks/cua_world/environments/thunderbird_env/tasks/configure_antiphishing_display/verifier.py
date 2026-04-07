#!/usr/bin/env python3
"""
Verifier for configure_antiphishing_display task.

Verification Strategy:
1. Programmatic Verification (75 points)
   - Read the exported JSON which parses `prefs.js` for 5 exact boolean/integer states.
   - Each successfully configured security policy grants 15 points.
   - File timestamp checks prevent "do nothing" gaming.
2. VLM Trajectory Verification (25 points)
   - Analyzes intermediate trajectory frames to confirm the agent actually navigated the Settings UI and View menu.
   - Ensures visual confirmation of UI-based progression.

Total possible: 100 points. Pass threshold: 60.
"""

import os
import json
import logging
import tempfile

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring Mozilla Thunderbird.
The agent was asked to enforce anti-phishing settings:
1. Message Body as Plain Text (View menu)
2. Show All Headers (View menu)
3. Disable condensed addresses (Settings tab)
4. Block remote content (Settings tab > Privacy & Security)
5. Disable document fonts (Settings tab > General > Advanced Fonts modal)

Look across the provided trajectory frames.
1. DID_INTERACT_UI: Does the sequence show the agent opening the 'Settings'/'Preferences' tab OR using the 'View' menu?
2. WORKFLOW_PROGRESS: Does the agent show progression across multiple dialogs or menus (not just staring at the Inbox)?

Respond in pure JSON format:
{
    "did_interact_ui": true/false,
    "workflow_progress": true/false,
    "reasoning": "brief explanation"
}"""


def verify_antiphishing_display(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_html_as = metadata.get('expected_html_as', 1)
    expected_show_headers = metadata.get('expected_show_headers', 2)
    expected_condensed = metadata.get('expected_condensed', False)
    expected_disable_remote = metadata.get('expected_disable_remote', True)
    expected_doc_fonts = metadata.get('expected_doc_fonts', 0)

    # 1. Retrieve programmatic results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    prefs = result.get("prefs", {})
    prefs_modified = result.get("prefs_modified_during_task", False)

    # Anti-gaming check
    if not prefs_modified:
        logger.warning("prefs.js was not modified during the task execution time.")
        # We will not early-fail fully, but VLM checks will heavily scrutinize this.
        # Often prefs.js writes can be cached; we gracefully closed Thunderbird, so it should be accurate.

    # 2. Programmatic checks (15 pts each)
    if prefs.get("html_as") == expected_html_as:
        score += 15
        feedback_parts.append("Plain text rendering verified")
    else:
        feedback_parts.append("Plain text rendering NOT configured")

    if prefs.get("show_headers") == expected_show_headers:
        score += 15
        feedback_parts.append("All headers exposed")
    else:
        feedback_parts.append("All headers NOT exposed")

    if prefs.get("condensed") == expected_condensed:
        score += 15
        feedback_parts.append("Full addresses exposed")
    else:
        feedback_parts.append("Full addresses NOT exposed")

    if prefs.get("disable_remote") == expected_disable_remote:
        score += 15
        feedback_parts.append("Remote content blocked")
    else:
        feedback_parts.append("Remote content NOT blocked")

    if prefs.get("doc_fonts") == expected_doc_fonts:
        score += 15
        feedback_parts.append("Custom document fonts disabled")
    else:
        feedback_parts.append("Custom document fonts NOT disabled")

    # 3. VLM Trajectory Check (25 pts)
    vlm_score = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            vlm_response = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("did_interact_ui"):
                    vlm_score += 15
                    feedback_parts.append("VLM: Verified UI interaction")
                if parsed.get("workflow_progress"):
                    vlm_score += 10
                    feedback_parts.append("VLM: Verified menu/dialog progression")
            else:
                logger.warning("VLM query failed or invalid.")
        except Exception as e:
            logger.error(f"VLM Exception: {e}")
            # If VLM errors out organically, we don't severely punish but log it.
            pass
    
    score += vlm_score

    # Passing criteria
    # Minimum of 3/5 programmatic settings must be applied (45 pts) + some UI progression, OR 4/5 strictly programmatic.
    key_criteria_met = prefs_modified and (score >= 60)
    passed = key_criteria_met

    if not prefs_modified:
        feedback_parts.append("WARNING: Preferences file timestamp unchanged (anti-gaming)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }