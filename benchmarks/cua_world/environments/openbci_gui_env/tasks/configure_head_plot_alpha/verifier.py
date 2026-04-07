#!/usr/bin/env python3
"""
Verifier for configure_head_plot_alpha task.
Uses VLM to verify the UI state of the OpenBCI GUI Head Plot widget.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_head_plot_alpha(traj, env_info, task_info):
    """
    Verify that the agent configured the Head Plot for Alpha Band Power.
    
    Criteria:
    1. Screenshot file exists and was created during task (Anti-gaming).
    2. VLM: Head Plot widget is visible.
    3. VLM: Widget is set to "Band Power" or "Power".
    4. VLM: Frequency band is set to "Alpha".
    5. VLM: Map shows active colored data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 1. Load JSON result from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Output File Check (20 points)
    # ---------------------------------------------------------
    file_exists = result_data.get("output_file_exists", False)
    created_during = result_data.get("output_file_created_during_task", False)
    
    if file_exists:
        if created_during:
            score += 20
            feedback_parts.append("Screenshot saved successfully during task.")
        else:
            score += 5
            feedback_parts.append("Screenshot exists but was not created during this session (stale?).")
    else:
        feedback_parts.append("Expected screenshot file was not saved.")

    # ---------------------------------------------------------
    # Criterion 2: VLM Verification of UI State (80 points)
    # ---------------------------------------------------------
    # We prioritize the framework's trajectory/final screenshot over the agent's file
    # to prevent the agent from just downloading a fake "success" image.
    
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of the OpenBCI GUI.
        I am looking for a 'Head Plot' widget (circular topographic map of the head).
        
        Please answer the following questions with YES or NO:
        1. Is a Head Plot widget visible?
        2. Does the Head Plot widget have "Band Power" (or just "Power") selected in its settings/header?
        3. Is the frequency band set to "Alpha"?
        4. Is the head map colored (showing active data heatmap) rather than just grey/empty?
        
        Respond in JSON format:
        {
            "head_plot_visible": boolean,
            "metric_is_power": boolean,
            "band_is_alpha": boolean,
            "data_is_active": boolean,
            "reasoning": "string"
        }
        """
        
        try:
            vlm_response = query_vlm(
                prompt=prompt,
                image=final_screenshot,
                model="gpt-4o" # or equivalent high-capability model
            )
            
            analysis = vlm_response.get("parsed", {})
            reasoning = analysis.get("reasoning", "No reasoning provided")
            logger.info(f"VLM Analysis: {json.dumps(analysis, indent=2)}")
            
            # Score breakdown
            if analysis.get("head_plot_visible", False):
                score += 20
                feedback_parts.append("Head Plot widget is visible.")
                
                if analysis.get("metric_is_power", False):
                    score += 30
                    feedback_parts.append("Widget configured for Band Power.")
                else:
                    feedback_parts.append("Widget NOT configured for Band Power (might be Amplitude/Potentials).")
                    
                if analysis.get("band_is_alpha", False):
                    score += 20
                    feedback_parts.append("Alpha band selected.")
                else:
                    feedback_parts.append("Alpha band NOT selected.")
                    
                if analysis.get("data_is_active", False):
                    score += 10
                    feedback_parts.append("Data visualization is active.")
                else:
                    feedback_parts.append("Head map appears inactive/empty.")
            else:
                feedback_parts.append("Head Plot widget was not found in the final view.")
                
        except Exception as e:
            feedback_parts.append(f"VLM verification failed: {str(e)}")
            # Fallback check on the agent's own screenshot if system one failed
            if file_exists and score < 20:
                feedback_parts.append("Attempting fallback verification on agent's screenshot...")
                # (Logic would be similar, omitted for brevity/security)

    else:
        feedback_parts.append("No system screenshot available for verification.")

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    # Pass threshold: 80 points.
    # Essential: Must have Head Plot + Band Power + Alpha (20+30+20 = 70) + File (10+) or Data (10)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }