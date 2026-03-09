#!/usr/bin/env python3
"""
Verifier for dual_axis_macro_plot task.

Criteria:
1. PNG image exists and was created during task (20 pts)
2. PLT script exists and was created during task (20 pts)
3. PLT script content analysis (35 pts):
   - Confirms 'g_gdp' (or derivative) and 'inf' are plotted
   - Confirms dual axis configuration (y2tics / axes x1y2)
4. Visual verification via VLM (25 pts):
   - Confirms image looks like a time series plot with two distinct series
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dual_axis_macro_plot(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check Files Existence & Timestamp (40 pts total)
    png_exists = result.get("png_exists", False)
    png_fresh = result.get("png_created_during_task", False)
    plt_exists = result.get("plt_exists", False)
    plt_fresh = result.get("plt_created_during_task", False)

    if png_exists and png_fresh:
        score += 20
        feedback.append("PNG image created successfully.")
    elif png_exists:
        score += 5
        feedback.append("PNG image exists but has old timestamp.")
    else:
        feedback.append("PNG image not found.")

    if plt_exists and plt_fresh:
        score += 20
        feedback.append("Gnuplot script created successfully.")
    elif plt_exists:
        score += 5
        feedback.append("Gnuplot script exists but has old timestamp.")
    else:
        feedback.append("Gnuplot script not found.")

    # 3. Analyze PLT Content (35 pts)
    # Only proceed if PLT exists
    if plt_exists:
        plt_content = ""
        temp_plt = tempfile.NamedTemporaryFile(delete=False, suffix='.plt')
        try:
            plt_path = result.get("plt_path")
            copy_from_env(plt_path, temp_plt.name)
            with open(temp_plt.name, 'r') as f:
                plt_content = f.read()
        except Exception as e:
            feedback.append(f"Failed to read PLT file: {e}")
        finally:
            if os.path.exists(temp_plt.name):
                os.unlink(temp_plt.name)

        if plt_content:
            # Check for dual axis settings
            # Gnuplot usually uses "set y2tics" and "axes x1y2"
            has_y2tics = "set y2tics" in plt_content
            has_x1y2 = "axes x1y2" in plt_content or "axes x1y2" in plt_content.replace("'", "").replace('"', "")
            
            if has_y2tics or has_x1y2:
                score += 20
                feedback.append("Dual Y-axis configuration detected in script.")
            else:
                feedback.append("Dual Y-axis configuration NOT detected in script.")

            # Check for variables
            # Look for plot command with variable names
            # User defined g_gdp, and existing inf
            # Note: Gretl might export column numbers or temporary file references, 
            # but usually includes title "varname"
            has_gdp_var = bool(re.search(r'title\s+["\']g_gdp["\']', plt_content, re.IGNORECASE))
            has_inf_var = bool(re.search(r'title\s+["\']inf["\']', plt_content, re.IGNORECASE))

            if has_gdp_var and has_inf_var:
                score += 15
                feedback.append("Correct variables (g_gdp, inf) found in plot script.")
            elif has_gdp_var or has_inf_var:
                score += 7
                feedback.append("One correct variable found in plot script.")
            else:
                feedback.append("Could not confirm variable names in plot script.")

    # 4. VLM Visual Verification (25 pts)
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        # We verify the FINAL SCREENSHOT or the PNG if we could retrieve it.
        # But retrieving PNG via copy_from_env for VLM is complex in this signature.
        # We'll use the final desktop screenshot which usually shows the result window or the agent's work.
        
        prompt = """
        Examine this screenshot of the Gretl econometrics software.
        1. Is there a time series plot visible?
        2. Does the plot show two distinct lines (series)?
        3. Is there evidence of a dual axis (scales on both left and right sides)?
        4. Do the variable names 'g_gdp' (or similar) and 'inf' appear in the legend or title?
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get("success"):
            # Simple heuristic parsing or human-in-the-loop simulation
            resp = vlm_res.get("response", "").lower()
            
            vlm_score = 0
            if "plot" in resp or "graph" in resp:
                vlm_score += 5
            if "two" in resp or "both" in resp or "2 lines" in resp:
                vlm_score += 10
            if "dual" in resp or "right axis" in resp or "right side" in resp or "scales" in resp:
                vlm_score += 10
                
            score += vlm_score
            feedback.append(f"VLM Visual check score: {vlm_score}/25")
        else:
            feedback.append("VLM check failed to run.")
    else:
        feedback.append("No final screenshot available for VLM check.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }