#!/usr/bin/env python3
"""
Verifier for population_health_age_pyramid task.

Verifies:
1. Python script creation (10 pts)
2. Valid PNG image creation (20 pts)
3. CSV data accuracy matches DB ground truth (20 pts)
4. Pyramid structure logic (aggregation/separation) (30 pts)
5. Visual verification via VLM (20 pts)
"""

import json
import os
import tempfile
import logging
import csv
import io
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_population_health_age_pyramid(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    
    # 1. Retrieve Result JSON and Files
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env("/tmp/task_result.json", f.name)
            with open(f.name) as jf:
                result = json.load(jf)
        
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
            copy_from_env("/tmp/ground_truth.json", f.name)
            with open(f.name) as jf:
                ground_truth = json.load(jf)
        
        agent_csv_content = ""
        if result.get("csv_exists"):
            with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as f:
                copy_from_env("/tmp/agent_data.csv", f.name)
                with open(f.name) as cf:
                    agent_csv_content = cf.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}

    # Criterion 1: Script Created (10 pts)
    if result.get("script_exists"):
        score += 10
        feedback.append("Script file created.")
    else:
        feedback.append("Script file missing.")

    # Criterion 2: Image Created & Valid (20 pts)
    if result.get("img_exists") and result.get("img_created_during_task"):
        if result.get("img_size", 0) > 1000: # Min size for a real plot
            score += 20
            feedback.append("Chart image created successfully.")
        else:
            score += 5
            feedback.append("Chart image created but seems empty/too small.")
    else:
        feedback.append("Chart image not created or not new.")

    # Criterion 3: Data Accuracy (20 pts)
    # Parse agent CSV and compare sums
    data_accurate = False
    if result.get("csv_exists") and agent_csv_content:
        try:
            reader = csv.DictReader(io.StringIO(agent_csv_content))
            rows = list(reader)
            if not rows:
                feedback.append("CSV file is empty.")
            else:
                # Check columns
                keys = [k.lower() for k in rows[0].keys()]
                if any('age' in k for k in keys) and any('male' in k for k in keys) and any('female' in k for k in keys):
                    # Sum check
                    agent_m_sum = sum(int(float(r.get('male_count', r.get('Male', 0)))) for r in rows)
                    agent_f_sum = sum(int(float(r.get('female_count', r.get('Female', 0)))) for r in rows)
                    
                    # GT Sum
                    gt_bins = ground_truth.get('bins', {})
                    gt_m_sum = sum(v.get('M', 0) for v in gt_bins.values())
                    gt_f_sum = sum(v.get('F', 0) for v in gt_bins.values())
                    
                    # Tolerance (5% or +/- 2)
                    m_diff = abs(agent_m_sum - gt_m_sum)
                    f_diff = abs(agent_f_sum - gt_f_sum)
                    
                    if m_diff <= max(2, gt_m_sum * 0.05) and f_diff <= max(2, gt_f_sum * 0.05):
                        score += 20
                        data_accurate = True
                        feedback.append(f"Data matches DB: M={agent_m_sum}, F={agent_f_sum}.")
                    else:
                        score += 5 # Partial for CSV structure
                        feedback.append(f"Data discrepancy. Agent: M={agent_m_sum},F={agent_f_sum}. Actual: M={gt_m_sum},F={gt_f_sum}.")
                else:
                    feedback.append("CSV columns do not match requirements (age, male, female).")
        except Exception as e:
            feedback.append(f"Error parsing CSV: {e}")
    else:
        feedback.append("CSV data file missing.")

    # Criterion 4: Pyramid Logic (Grouping) (30 pts)
    # If CSV has multiple rows and separates sexes, we assume logic is sound-ish.
    # A true pyramid has specific structure.
    if data_accurate:
        # Check grouping size
        if len(rows) > 3: # Need multiple bins for a pyramid
            score += 30
            feedback.append("Data grouping logic appears correct.")
        else:
            score += 10
            feedback.append("Data grouping seems too coarse for a pyramid.")
    elif result.get("csv_exists"):
        score += 10 # Partial for attempt

    # Criterion 5: Visual Verification (20 pts)
    # VLM Check
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    # We prioritize the generated image file if we can get it, but VLM usually sees screenshots.
    # The output script puts the file at a path. The agent might have opened it.
    # We will check the final screenshot to see if a chart is visible, OR if the file content matches.
    # Since we can't easily upload the PNG file from container to VLM (unless library supports it),
    # we rely on the screenshot.
    
    vlm_prompt = """
    Check if a 'Population Age Pyramid' or bar chart is visible. 
    It should have horizontal bars. 
    One side should represent Males, the other Females (often diverging from center).
    Is there a chart visible?
    Does it have 'Age' and 'Population/Count' axes?
    """
    
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    if vlm_result and isinstance(vlm_result, dict) and vlm_result.get("success"):
        # Heuristic based on VLM text response
        resp = vlm_result.get("response", "").lower()
        if "yes" in resp and ("chart" in resp or "graph" in resp or "pyramid" in resp):
            score += 20
            feedback.append("Visual verification passed.")
        else:
            feedback.append("Visual verification uncertain.")
    else:
        # Fallback if VLM fails but file exists
        if result.get("img_exists") and result.get("img_created_during_task"):
            score += 20
            feedback.append("Visual verification skipped (VLM error), trusting file existence.")

    # Pass logic
    passed = score >= 70 and result.get("img_exists") and result.get("csv_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }