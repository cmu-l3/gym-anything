#!/usr/bin/env python3
"""
Verifier for enable_katex_math_rendering task.

Verification Strategy:
1. Programmatic API Check (Primary): Verify KaTeX toggles are enabled and the message was posted.
2. VLM Trajectory Check (Secondary): Ensure the agent naturally navigated the workflow (anti-gaming).
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing VLM tools (graceful degradation if missing)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False


def verify_enable_katex_math_rendering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_msg = metadata.get('target_message', "The final equation is $E = mc^2$")

    # 1. Read programmatic export results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # API Criteria 1: Main KaTeX Setting (15 pts)
    if result.get('katex_enabled', False):
        score += 15
        feedback.append("KaTeX Enabled: Yes (+15)")
    else:
        feedback.append("KaTeX Enabled: No")

    # API Criteria 2: Dollar Syntax Setting (15 pts)
    if result.get('katex_dollar_syntax', False):
        score += 15
        feedback.append("Dollar Syntax: Yes (+15)")
    else:
        feedback.append("Dollar Syntax: No")

    # API Criteria 3: Parenthesis Syntax Setting (15 pts)
    if result.get('katex_parenthesis_syntax', False):
        score += 15
        feedback.append("Parenthesis Syntax: Yes (+15)")
    else:
        feedback.append("Parenthesis Syntax: No")

    # API Criteria 4: Validation Message Posted (25 pts)
    msg_found = result.get('message_found', False)
    msg_text = result.get('message_text', "")

    if msg_found and "$E = mc^2$" in msg_text:
        score += 25
        feedback.append("Target Message Found: Yes (+25)")
    elif msg_found:
        score += 10
        feedback.append(f"Target Message Found: Partial match ('{msg_text}') (+10)")
    else:
        feedback.append("Target Message Found: No")

    # 2. VLM Trajectory Verification (30 pts)
    vlm_score = 0
    if VLM_AVAILABLE:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames

        if images:
            prompt = """You are analyzing a sequence of screenshots from an agent interacting with Rocket.Chat.
            Assess the following steps in the workflow:
            1. Did the agent navigate to the Administration panel (e.g., Workspace > Settings)?
            2. Did the agent interact with the KaTeX configuration or Message parser toggles?
            3. Did the agent post a message in a chat channel containing a mathematical formula (e.g., $E = mc^2$)?
            
            Respond in JSON format:
            {
                "navigated_to_settings": true/false,
                "toggled_katex": true/false,
                "posted_message": true/false
            }"""
            
            try:
                vlm_result = query_vlm(prompt=prompt, images=images)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("navigated_to_settings"): vlm_score += 10
                    if parsed.get("toggled_katex"): vlm_score += 10
                    if parsed.get("posted_message"): vlm_score += 10
                    feedback.append(f"VLM Verification Score: {vlm_score}/30")
                else:
                    feedback.append("VLM Verification: Failed to parse query")
            except Exception as e:
                feedback.append(f"VLM Verification error: {e}")
        else:
            feedback.append("VLM Verification: Skipped (no trajectory images found)")
    else:
        feedback.append("VLM Verification: Skipped (tools unavailable)")
        # Normalize score if VLM is completely missing from the test bed
        score = int(score * (100.0 / 70.0))

    score += vlm_score

    # Calculate Pass Threshold (75 points out of 100)
    passed = score >= 75 and result.get('katex_enabled', False) and result.get('message_found', False)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }