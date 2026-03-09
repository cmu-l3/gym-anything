#!/usr/bin/env python3
import json
import logging
import os
import tempfile
import re
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interpolate_virtual_gauge_results(traj, env_info, task_info):
    """
    Verify the interpolation of virtual gauge results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy access failed"}

    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files = result.get('files', {})
    ground_truth = result.get('ground_truth', {})
    
    if "error" in ground_truth:
        return {"passed": False, "score": 0, "feedback": f"System error generating ground truth: {ground_truth['error']}"}

    # 1. Script Creation (10 pts)
    if files.get('script', {}).get('exists'):
        score += 5
        if files.get('script', {}).get('created_during_task'):
            score += 5
            feedback.append("Analysis script created.")
        else:
            feedback.append("Analysis script exists but timestamp is old.")
    else:
        feedback.append("Analysis script missing.")

    # 2. Info File Validation (30 pts)
    # Expected format: Upstream Station: X \n Downstream Station: Y \n Target Station: Z
    info_content = files.get('info', {}).get('content', '')
    gt_us = ground_truth.get('upstream_rs')
    gt_ds = ground_truth.get('downstream_rs')
    gt_tg = ground_truth.get('target_rs')
    
    stations_correct = False
    target_correct = False
    
    if info_content:
        # Regex to find numbers associated with keys
        us_match = re.search(r'Upstream.*?(\d+\.?\d*)', info_content, re.IGNORECASE)
        ds_match = re.search(r'Downstream.*?(\d+\.?\d*)', info_content, re.IGNORECASE)
        tg_match = re.search(r'Target.*?(\d+\.?\d*)', info_content, re.IGNORECASE)
        
        if us_match and ds_match and tg_match:
            try:
                agent_us = float(us_match.group(1))
                agent_ds = float(ds_match.group(1))
                agent_tg = float(tg_match.group(1))
                
                # Check Stations (Tolerance 0.1)
                if abs(agent_us - gt_us) < 0.1 and abs(agent_ds - gt_ds) < 0.1:
                    score += 20
                    stations_correct = True
                    feedback.append(f"Correct stations identified: {gt_us}, {gt_ds}")
                else:
                    feedback.append(f"Incorrect stations. Expected {gt_us}, {gt_ds}. Got {agent_us}, {agent_ds}")
                
                # Check Target
                if abs(agent_tg - gt_tg) < 0.1:
                    score += 10
                    target_correct = True
                    feedback.append(f"Correct target station calculated: {gt_tg}")
                else:
                    feedback.append(f"Incorrect target. Expected {gt_tg}. Got {agent_tg}")
            except ValueError:
                feedback.append("Could not parse numbers from info file.")
        else:
            feedback.append("Info file format incorrect. Could not find Upstream/Downstream/Target patterns.")
    else:
        feedback.append("Info file missing or empty.")

    # 3. CSV Data Validation (60 pts)
    csv_head = files.get('csv', {}).get('head', '')
    csv_exists = files.get('csv', {}).get('exists')
    
    data_accurate = False
    
    if csv_exists and csv_head:
        score += 10 # CSV exists
        
        # Parse head to check data
        # We only check the first few rows available in the head against the ground truth series
        # Ground truth has 'wse_series' (list of floats)
        gt_series = ground_truth.get('wse_series', [])
        
        agent_values = []
        lines = csv_head.strip().split('\n')
        
        # Skip header if present
        start_idx = 0
        if "time" in lines[0].lower() or "wse" in lines[0].lower():
            start_idx = 1
            
        for line in lines[start_idx:]:
            if not line.strip(): continue
            parts = line.split(',')
            if len(parts) >= 2:
                try:
                    # Assuming col 2 is WSE
                    agent_values.append(float(parts[1]))
                except:
                    pass
        
        # Compare
        if len(agent_values) > 0 and len(gt_series) > 0:
            count = min(len(agent_values), len(gt_series))
            diffs = [abs(agent_values[i] - gt_series[i]) for i in range(count)]
            rmse = math.sqrt(sum([d*d for d in diffs]) / count)
            
            if rmse < 0.05: # 0.05 ft tolerance
                score += 50
                data_accurate = True
                feedback.append(f"Data accuracy verification passed. RMSE: {rmse:.4f}")
            else:
                feedback.append(f"Data accuracy failed. RMSE: {rmse:.4f} (Tolerance 0.05)")
                # Debug info
                feedback.append(f"First 3 Agent: {agent_values[:3]}")
                feedback.append(f"First 3 Truth: {gt_series[:3]}")
        else:
            feedback.append("Could not extract data from CSV for verification.")
    else:
        feedback.append("CSV file missing or empty.")

    passed = (score >= 70) and stations_correct and data_accurate
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }