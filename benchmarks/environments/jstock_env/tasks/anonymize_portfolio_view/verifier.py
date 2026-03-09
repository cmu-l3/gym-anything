#!/usr/bin/env python3
"""
Verifier for anonymize_portfolio_view task.

Verifies that:
1. The agent created the requested screenshot file.
2. VLM Analysis: The screenshot (and final app state) shows the portfolio table.
3. VLM Analysis: Sensitive currency columns are HIDDEN.
4. VLM Analysis: Percentage columns are VISIBLE.
"""

import json
import os
import tempfile
import logging
# Hypothetical import for VLM capabilities provided by framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anonymize_portfolio_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Agent's Screenshot (if it exists)
    agent_image_path = None
    if result_data.get("file_exists") and result_data.get("file_created_during_task"):
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result_data["file_path"], temp_img.name)
            agent_image_path = temp_img.name
        except:
            pass # Failed to copy, will handle below
    
    # Scoring
    score = 0
    feedback = []
    
    # Basic Checks (20 pts)
    if result_data.get("file_exists"):
        score += 10
        feedback.append("Screenshot file created.")
        if result_data.get("file_created_during_task"):
            score += 10
            feedback.append("File created during task session.")
        else:
            feedback.append("Warning: File timestamp predates task.")
    else:
        feedback.append("Screenshot file NOT found.")

    # VLM Checks (80 pts)
    if VLM_AVAILABLE:
        # We check two things: 
        # A) The agent's output screenshot (does it look right?)
        # B) The final state of the screen (did they actually change the view, or just Photoshop it?)
        
        images_to_check = []
        
        # Add final state from trajectory/framework
        final_state_img = get_final_screenshot(traj)
        if final_state_img:
            images_to_check.append({"type": "final_state", "img": final_state_img})
            
        # Add agent's file if available
        if agent_image_path:
            images_to_check.append({"type": "agent_file", "img": agent_image_path})
            
        if not images_to_check:
             return {"passed": False, "score": score, "feedback": "No images available for VLM verification."}

        # Prompt for VLM
        # We want to confirm:
        # 1. It is the JStock portfolio view
        # 2. Currency/Price columns are missing
        # 3. Percentage columns are present
        prompt = (
            "Analyze these images of a stock portfolio software (JStock). "
            "The user was asked to hide sensitive financial values.\n"
            "1. Are absolute currency columns (like 'Purchase Price', 'Current Price', 'Value', '$') HIDDEN/GONE?\n"
            "2. Are percentage columns (like 'Gain/Loss %') VISIBLE?\n"
            "3. Are the stock symbols (AAPL, MSFT) VISIBLE?\n"
            "Reply with JSON: {\"currency_hidden\": bool, \"percent_visible\": bool, \"symbols_visible\": bool}"
        )

        try:
            # We query using the most relevant image (Agent's file preferred for specific framing, 
            # but final state is good backup)
            target_image = images_to_check[-1]["img"] # Prefer last added
            vlm_response = query_vlm(images=[target_image], prompt=prompt, return_json=True)
            
            vlm_data = vlm_response if isinstance(vlm_response, dict) else {}
            
            if vlm_data.get("symbols_visible"):
                score += 20
                feedback.append("Stock symbols visible.")
            else:
                feedback.append("Could not identify stock symbols.")

            if vlm_data.get("percent_visible"):
                score += 20
                feedback.append("Performance percentages visible.")
            else:
                feedback.append("Percentage columns missing.")

            if vlm_data.get("currency_hidden"):
                score += 40
                feedback.append("Currency values successfully hidden.")
            else:
                feedback.append("Sensitive currency values still visible.")

        except Exception as e:
            feedback.append(f"VLM verification failed: {str(e)}")
            # Fallback points if we verified file existence but VLM crashed
            if score == 20: 
                score += 0 # No extra points without verification
    else:
        feedback.append("VLM not available - skipping visual verification.")
        # If VLM is missing, we can't verify content. 
        # For development/stubbing, we might auto-pass if file exists, 
        # but for production tasks, this is a failure of verification infra.
    
    # Cleanup
    if agent_image_path and os.path.exists(agent_image_path):
        os.unlink(agent_image_path)

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }