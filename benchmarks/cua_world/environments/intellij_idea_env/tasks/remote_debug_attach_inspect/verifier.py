#!/usr/bin/env python3
"""
Verifier for remote_debug_attach_inspect task.

Scoring:
1. Token Correctness (50 pts): The text file contains the exact runtime token.
   - This proves the agent successfully inspected the variable.
   - Since the token is random and generated at runtime, it cannot be guessed.

2. Configuration Check (20 pts): A Remote Debug configuration was created.
   - Checked via XML files in .idea.

3. VLM Workflow Verification (30 pts):
   - Uses trajectory frames to verify the debugging process.
   - Checks for: Debug tool window, Suspended state, Variables view.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remote_debug(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read programmatic result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Token Match (50 pts) ---
    token_match = result.get('token_match', False)
    if token_match:
        score += 50
        feedback_parts.append("Success: Correct runtime token identified.")
    else:
        actual = result.get('output_content', 'None')
        expected = result.get('ground_truth', 'Unknown')
        feedback_parts.append(f"Fail: Token mismatch. Submitted: '{actual}', Expected: '{expected}'")

    # --- Criterion 2: Run Configuration (20 pts) ---
    config_exists = result.get('run_config_exists', False)
    if config_exists:
        score += 20
        feedback_parts.append("Remote debug configuration detected.")
    else:
        feedback_parts.append("No 'Remote' run configuration found in project settings.")

    # --- Criterion 3: VLM Verification of Debugging UI (30 pts) ---
    # We use VLM to ensure the agent actually used the debugger and didn't just 
    # somehow cat the memory or use other tricks (though difficult).
    # More importantly, it verifies the *process* of debugging.
    
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    # Get frames from across the trajectory
    frames = sample_trajectory_frames(traj, num_samples=5)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm and frames:
        prompt = """
        You are verifying a Java debugging task in IntelliJ IDEA.
        Look at these screenshots of the agent's workflow.
        
        I need to confirm three things:
        1. DEBUG_TOOL_WINDOW: Is the 'Debug' tool window visible (usually at the bottom)?
        2. SUSPENDED_STATE: Is the execution paused? Look for a highlighted line of code in the editor (usually blue or red background) and 'Variables' shown in the debug pane.
        3. VARIABLES_VISIBLE: Can you see a list of variables (like 'this', 'id', 'token') in the debug pane?
        
        Respond in JSON:
        {
            "debug_window_visible": true/false,
            "suspended_state_visible": true/false,
            "variables_visible": true/false,
            "reasoning": "..."
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, images=frames)
            if vlm_resp and vlm_resp.get('success'):
                analysis = vlm_resp.get('parsed', {})
                
                if analysis.get('debug_window_visible'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Debug tool window observed.")
                
                if analysis.get('suspended_state_visible'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Execution suspension observed.")
                    
                if analysis.get('variables_visible'):
                    vlm_score += 10
                    feedback_parts.append("VLM: Variables inspection observed.")
            else:
                feedback_parts.append("VLM verification failed (API error).")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            feedback_parts.append("VLM verification skipped due to error.")
    else:
        feedback_parts.append("VLM verification skipped (no frames/API).")
        # Fallback: if token matched, give partial credit for VLM
        if token_match:
            vlm_score += 15
            feedback_parts.append("Fallback: Awarding partial VLM points due to correct token.")

    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 70) and token_match
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }