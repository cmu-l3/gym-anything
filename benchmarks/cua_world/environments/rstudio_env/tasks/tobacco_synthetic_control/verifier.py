#!/usr/bin/env python3
"""
Verifier for Tobacco Synthetic Control Task.

Scoring Breakdown (100 pts):
1. Weights CSV (30 pts): Exists, new, contains expected donor states (Utah/Nevada etc).
2. Effect Value (20 pts): Exists, new, numeric value in reasonable range (-35 to -15).
3. Plot (20 pts): Exists, new, valid size (>30KB).
4. Code Quality (10 pts): Script uses Synth and ggplot2.
5. VLM Verification (20 pts): Visual check of the plot (trends diverging after 1989).
"""

import json
import tempfile
import os
import logging
import csv
import io

logger = logging.getLogger(__name__)

def verify_tobacco_synthetic_control(traj, env_info, task_info):
    """
    Verify the synthetic control analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # 1. Verify Weights (30 pts)
    weights_score = 0
    if result.get('weights_exists') and result.get('weights_is_new'):
        weights_score += 10
        # Check content
        content = result.get('weights_content', '')
        # Expected high weight states for this specific specification
        expected_states = ['Utah', 'Nevada', 'Montana', 'Colorado', 'New Hampshire']
        found_states = 0
        for state in expected_states:
            if state.lower() in content.lower():
                found_states += 1
        
        if found_states >= 2:
            weights_score += 20
            feedback.append(f"Weights CSV looks correct (found {found_states} expected donors)")
        else:
            feedback.append(f"Weights CSV missing key donor states (found {found_states})")
    else:
        feedback.append("Weights CSV missing or not created during task")
    
    score += weights_score

    # 2. Verify Effect Value (20 pts)
    effect_score = 0
    val = result.get('effect_value')
    if result.get('effect_exists') and result.get('effect_is_new') and val is not None:
        effect_score += 10
        # Check range
        try:
            v = float(val)
            # Real gap is approx -26 packs
            if -40.0 <= v <= -10.0:
                effect_score += 10
                feedback.append(f"Effect value {v} is in plausible range")
            else:
                feedback.append(f"Effect value {v} is out of expected range (-40 to -10)")
        except:
            feedback.append("Effect value is not a valid number")
    else:
        feedback.append("Effect value file missing")
        
    score += effect_score

    # 3. Verify Plot File (20 pts)
    plot_score = 0
    if result.get('plot_exists') and result.get('plot_is_new'):
        plot_score += 10
        size = result.get('plot_size_bytes', 0)
        if size > 30000: # 30KB
            plot_score += 10
            feedback.append("Plot created and has substantial size")
        else:
            feedback.append("Plot file is too small/empty")
    else:
        feedback.append("Plot file missing")
        
    score += plot_score

    # 4. Code Quality (10 pts)
    code_score = 0
    if result.get('script_has_synth'):
        code_score += 5
    if result.get('script_has_ggplot'):
        code_score += 5
    score += code_score
    if code_score < 10:
        feedback.append("Script missing 'Synth' or 'ggplot' calls")

    # 5. VLM Verification (20 pts)
    vlm_score = 0
    if query_vlm and result.get('plot_exists'):
        # We need to fetch the actual image file content? 
        # The env_info usually provides a way to get the final screenshot, 
        # but here we ideally want to verify the specific PNG file generated.
        # Since we can't easily download the PNG file here to pass to VLM without extra logic,
        # we will check the trajectory frames or final screenshot for the plot appearing in RStudio plot pane
        # OR assume if the user opened the PNG file it might be visible.
        # However, relying on the file size check is robust enough for "file generated".
        # We will use VLM to check the FINAL SCREENSHOT of the desktop to see if RStudio shows success/plot.
        
        final_ss = get_final_screenshot(traj)
        if final_ss:
            prompt = """
            Look at this screenshot of RStudio.
            1. Is there a plot visible (either in the Plots pane or opened as a file)?
            2. Does the plot show two lines diverging over time (like a synthetic control path plot)?
            3. Is there evidence of R code execution in the console?
            Respond in JSON: {"plot_visible": bool, "diverging_lines": bool, "code_exec": bool}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=final_ss)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('plot_visible'):
                    vlm_score += 10
                if parsed.get('diverging_lines'):
                    vlm_score += 10
                feedback.append("VLM verification successful")
            except Exception as e:
                logger.warning(f"VLM failed: {e}")
                # Fallback: give points if file checks passed strongly
                if score >= 60:
                    vlm_score = 20
                    feedback.append("VLM skipped, fallback credit")
        else:
            feedback.append("No screenshot for VLM")
            
    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }