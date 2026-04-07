#!/usr/bin/env python3
"""
Verifier for ozone_gam_environmental task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are evaluating an AI agent's performance in RStudio on a data analysis task involving Generalized Additive Models (GAMs).
Please look at the trajectory screenshots.

Did the agent:
1. Write R code utilizing the `mgcv` package (functions like `gam` and `s()`)?
2. Execute the code (e.g., console output visible showing model summaries)?
3. Create a plot showing smooth curves (partial effects) in the RStudio Plots pane?

Provide your assessment in the following JSON format:
{
    "wrote_code": true/false,
    "executed_code": true/false,
    "created_plot": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "Brief explanation"
}
"""

def verify_ozone_gam(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load JSON result safely
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Script checks (20 pts)
    script_pts = 0
    if result.get('script_exists') and result.get('script_modified'):
        script_pts += 5
        feedback.append("Script modified (+5)")
    if result.get('has_mgcv'):
        script_pts += 5
        feedback.append("Used mgcv package (+5)")
    if result.get('has_gam'):
        script_pts += 5
        feedback.append("Used gam() function (+5)")
    if result.get('has_s'):
        script_pts += 5
        feedback.append("Used s() function for smooths (+5)")
    score += script_pts

    # 2. CSV checks (20 pts)
    csv_pts = 0
    if result.get('csv_exists') and result.get('csv_is_new'):
        csv_pts += 10
        feedback.append("Comparison CSV created (+10)")
    
    lm_aic_str = result.get('lm_aic', 'inf')
    gam_aic_str = result.get('gam_aic', 'inf')
    try:
        lm_aic = float(lm_aic_str)
        gam_aic = float(gam_aic_str)
        if gam_aic < lm_aic and gam_aic != float('inf'):
            csv_pts += 10
            feedback.append(f"GAM AIC ({gam_aic}) is lower than LM AIC ({lm_aic}) (+10)")
        elif gam_aic != float('inf') and lm_aic != float('inf'):
            feedback.append(f"GAM AIC ({gam_aic}) is not lower than LM AIC ({lm_aic}) (0)")
    except Exception:
        pass
    score += csv_pts

    # 3. Prediction checks (20 pts)
    pred_pts = 0
    if result.get('txt_exists') and result.get('txt_is_new'):
        pred_pts += 5
        feedback.append("Prediction TXT created (+5)")
        
    pred_str = result.get('prediction', '')
    if pred_str:
        try:
            pred_val = float(pred_str)
            # Acceptable range for high risk day prediction (typically around 90-110 depending on exact handling)
            if 60 <= pred_val <= 150:
                pred_pts += 15
                feedback.append(f"Prediction {pred_val} is within plausible range (60-150) (+15)")
            else:
                feedback.append(f"Prediction {pred_val} is outside plausible range (60-150) (0)")
        except ValueError:
            feedback.append("Could not parse numeric prediction (0)")
    score += pred_pts

    # 4. Plot checks (20 pts)
    plot_pts = 0
    if result.get('png_exists') and result.get('png_is_new'):
        plot_pts += 10
        feedback.append("Plot PNG created (+10)")
        png_size = result.get('png_size_kb', 0)
        if png_size > 5:
            plot_pts += 10
            feedback.append(f"Plot size is substantial ({png_size}KB) (+10)")
        else:
            feedback.append(f"Plot file is too small ({png_size}KB) (0)")
    score += plot_pts

    # 5. VLM Trajectory (20 pts)
    vlm_pts = 0
    if query_vlm:
        try:
            try:
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=5)
            except ImportError:
                # Fallback if specific function missing
                from gym_anything.vlm import get_final_screenshot
                frames = [get_final_screenshot(traj)]
                
            if frames:
                vlm_resp = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("wrote_code") or parsed.get("executed_code"):
                        vlm_pts += 10
                        feedback.append("VLM confirmed R code writing/execution (+10)")
                    if parsed.get("created_plot"):
                        vlm_pts += 10
                        feedback.append("VLM confirmed plot generation (+10)")
                    score += vlm_pts
                else:
                    feedback.append("VLM query did not succeed.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback.append("VLM verification skipped due to error.")

    # Pass threshold: 60 pts and required output files exist
    essential_met = (result.get('csv_exists') and result.get('png_exists') and result.get('txt_exists'))
    passed = (score >= 60) and essential_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }