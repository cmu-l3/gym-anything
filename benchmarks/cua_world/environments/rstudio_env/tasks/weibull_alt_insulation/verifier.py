#!/usr/bin/env python3
"""
Verifier for Weibull ALT Insulation task.

Scoring (100 points total):
1. Weibull Params CSV (30 pts):
   - Exists & New (5)
   - Contains all 4 test temps (5)
   - Shape parameter > 1.0 (5)
   - Scale decreases as temp increases (10)
   - B10 values present (5)

2. Prediction CSV (30 pts):
   - Exists & New (5)
   - Contains prediction for 180 C (10)
   - B10 @ 180 > B10 @ 190 (correct direction) (10)
   - B10 @ 180 in plausible range (5k - 100k) (5)

3. Plot (15 pts):
   - Exists & New (5)
   - Size > 30KB (10)

4. Script (10 pts):
   - Modified (10)

5. VLM Bonus (15 pts):
   - Visual confirmation of analysis workflow

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_weibull_alt_insulation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    tmp_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []

    # --- 1. Weibull Params CSV (30 pts) ---
    params = result.get('params_csv', {})
    params_data = params.get('data', [])
    
    if params.get('exists') and params.get('is_new'):
        score += 5
        feedback.append("Params CSV created (+5)")
    else:
        feedback.append("Params CSV missing or old (0)")

    # Check content
    temps_found = set()
    scales = {} # Map temp -> scale
    shapes_valid = True
    b10_present = True

    for row in params_data:
        try:
            # Handle variations in column names via flexible lookup
            t_key = next((k for k in row.keys() if 'temp' in k), None)
            s_key = next((k for k in row.keys() if 'scale' in k), None)
            b_key = next((k for k in row.keys() if 'shape' in k), None)
            b10_key = next((k for k in row.keys() if 'b10' in k), None)

            if t_key:
                t = float(row[t_key])
                temps_found.add(int(t))
                if s_key:
                    scales[int(t)] = float(row[s_key])
                if b_key and float(row[b_key]) <= 1.0:
                    shapes_valid = False
                if not b10_key or row[b10_key] == '':
                    b10_present = False
        except ValueError:
            continue

    if {190, 220, 240, 260}.issubset(temps_found):
        score += 5
        feedback.append("All test temperatures present (+5)")
    else:
        feedback.append(f"Missing test temperatures. Found: {temps_found} (0)")

    if shapes_valid and len(params_data) > 0:
        score += 5
        feedback.append("Weibull shapes > 1.0 (wear-out) (+5)")
    
    # Check monotonicity of scale (should decrease as temp increases)
    sorted_temps = sorted(scales.keys())
    if len(sorted_temps) >= 3:
        monotonic = True
        for i in range(len(sorted_temps)-1):
            if scales[sorted_temps[i]] <= scales[sorted_temps[i+1]]:
                monotonic = False
        if monotonic:
            score += 10
            feedback.append("Scale decreases with temperature (+10)")
        else:
            feedback.append("Scale does not decrease monotonically with temperature (0)")
    
    if b10_present and len(params_data) > 0:
        score += 5
        feedback.append("B10 life values included (+5)")


    # --- 2. Prediction CSV (30 pts) ---
    pred = result.get('pred_csv', {})
    pred_data = pred.get('data', [])

    if pred.get('exists') and pred.get('is_new'):
        score += 5
        feedback.append("Prediction CSV created (+5)")
    
    pred_180_b10 = None
    
    for row in pred_data:
        try:
            t_key = next((k for k in row.keys() if 'temp' in k), None)
            b10_key = next((k for k in row.keys() if 'b10' in k), None)
            
            if t_key and b10_key:
                t = float(row[t_key])
                if int(t) == 180:
                    pred_180_b10 = float(row[b10_key])
        except ValueError:
            continue

    if pred_180_b10 is not None:
        score += 10
        feedback.append("Prediction for 180 C found (+10)")
        
        # Physics check: Life at 180 should be higher than at 190
        # Typical B10 at 190 is ~6000-7000. 
        # So 180 should be > 6000.
        if pred_180_b10 > 6000:
            score += 10
            feedback.append("Extrapolation direction correct (Life increases at lower temp) (+10)")
        else:
            feedback.append(f"Implausible prediction: B10 at 180C ({pred_180_b10}) not > 6000 (0)")

        # Range check (5000 to 100,000)
        if 5000 <= pred_180_b10 <= 100000:
            score += 5
            feedback.append("Prediction in plausible range (+5)")
    else:
        feedback.append("180 C prediction missing (0)")


    # --- 3. Plot (15 pts) ---
    plot = result.get('plot', {})
    if plot.get('exists') and plot.get('is_new'):
        score += 5
        feedback.append("Plot created (+5)")
        if plot.get('size_bytes', 0) > 30000:
            score += 10
            feedback.append("Plot size substantial (>30KB) (+10)")
        else:
            feedback.append("Plot file too small (0)")
    else:
        feedback.append("Plot missing (0)")


    # --- 4. Script (10 pts) ---
    if result.get('script_modified'):
        score += 10
        feedback.append("Script modified (+10)")
    else:
        feedback.append("Script not modified (0)")
        
    # --- 5. VLM Bonus (15 pts) ---
    # Using trajectory frames to verify meaningful work
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames
    
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Analyze these RStudio screenshots. 
            Do you see:
            1. R code relating to Weibull analysis (e.g. survreg, fitdist, plot)?
            2. Probability plots or Arrhenius plots appearing in the plot pane?
            
            Return JSON: {"has_weibull_code": bool, "has_plots": bool}
            """
            try:
                vlm_res = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('has_weibull_code'):
                    vlm_score += 10
                    feedback.append("VLM: Weibull code detected (+10)")
                if parsed.get('has_plots'):
                    vlm_score += 5
                    feedback.append("VLM: Plots detected (+5)")
            except Exception:
                pass
    
    score += vlm_score

    # Final tally
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": min(100, score), # Cap at 100
        "feedback": "; ".join(feedback)
    }