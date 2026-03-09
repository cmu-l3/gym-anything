#!/usr/bin/env python3
"""
Verifier for generate_asset_flood_timeline task.

This verifier compares the agent's CSV output against a ground truth JSON
generated during task setup.

Scoring Criteria:
- File Existence: 10 pts
- All Assets Present: 10 pts
- Status Accuracy (Flooded/Safe): 30 pts
- Timing Accuracy (Onset within tolerance): 20 pts
- Depth Accuracy (Peak Depth within tolerance): 20 pts
- Sorting/Formatting: 10 pts
"""

import json
import pandas as pd
import numpy as np
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_asset_flood_timeline(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result_meta.get('output_exists', False)
    ground_truth_exists = result_meta.get('ground_truth_exists', False)

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file flood_timeline.csv not found."}
    
    if not ground_truth_exists:
        return {"passed": False, "score": 0, "feedback": "Critical Error: Ground truth file missing. Task setup failed."}

    # 2. Fetch Agent Output and Ground Truth
    agent_csv_path = result_meta.get('output_csv_path', '/tmp/agent_output.csv')
    gt_json_path = result_meta.get('ground_truth_path', '/tmp/ground_truth.json')

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env(agent_csv_path, temp_csv.name)
        copy_from_env(gt_json_path, temp_gt.name)
        
        # Load Data
        try:
            agent_df = pd.read_csv(temp_csv.name)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"Output file exists but is not a valid CSV: {e}"}

        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
            gt_df = pd.DataFrame(gt_data)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading data files: {e}"}
    finally:
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    # 3. Scoring Logic
    score = 10  # Base score for file existence
    feedback = ["File exists."]
    
    # Check for required columns
    required_cols = ['Asset_Name', 'Flooded', 'Time_of_Onset_Hours', 'Peak_Depth_Above_Threshold_ft', 'Flood_Duration_Hours']
    missing_cols = [c for c in required_cols if c not in agent_df.columns]
    
    if missing_cols:
        feedback.append(f"Missing columns: {', '.join(missing_cols)}")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Merge for comparison
    # Normalize Asset_Name to handle whitespace issues
    agent_df['Asset_Name'] = agent_df['Asset_Name'].astype(str).str.strip()
    gt_df['Asset_Name'] = gt_df['Asset_Name'].astype(str).str.strip()
    
    merged = agent_df.merge(gt_df, on='Asset_Name', suffixes=('_agent', '_truth'), how='inner')
    
    # Criterion: All Assets Processed (10 pts)
    if len(merged) == len(gt_df):
        score += 10
        feedback.append("All assets processed.")
    else:
        feedback.append(f"Processed {len(merged)}/{len(gt_df)} assets.")

    # Criterion: Status Accuracy (30 pts)
    # Convert 'Flooded' to boolean to be safe
    merged['Flooded_agent'] = merged['Flooded_agent'].astype(str).str.lower().map({'true': True, 'false': False, '1': True, '0': False})
    # Handle NaN if map failed (though it shouldn't if agent followed instructions)
    
    status_matches = merged[merged['Flooded_agent'] == merged['Flooded_truth']]
    status_score = (len(status_matches) / len(gt_df)) * 30
    score += status_score
    if len(status_matches) == len(gt_df):
        feedback.append("Flood status correct for all assets.")
    else:
        feedback.append(f"Flood status correct for {len(status_matches)}/{len(gt_df)} assets.")

    # Criterion: Timing Accuracy (20 pts)
    # Only check timing for flooded assets
    flooded_gt = merged[merged['Flooded_truth'] == True]
    if len(flooded_gt) > 0:
        # Tolerance: +/- 0.25 hours (15 mins)
        # Handle N/A or empty strings in agent output
        flooded_gt['Time_of_Onset_Hours_agent'] = pd.to_numeric(flooded_gt['Time_of_Onset_Hours_agent'], errors='coerce').fillna(-999)
        
        timing_diff = np.abs(flooded_gt['Time_of_Onset_Hours_agent'] - flooded_gt['Time_of_Onset_Hours_truth'])
        timing_matches = timing_diff <= 0.25
        timing_score = (timing_matches.sum() / len(flooded_gt)) * 20
        score += timing_score
        feedback.append(f"Timing correct for {timing_matches.sum()}/{len(flooded_gt)} flooded assets.")
    else:
        # If no assets flood, give full points for timing (trivial case)
        score += 20
        feedback.append("No flooding expected; timing skipped.")

    # Criterion: Depth Accuracy (20 pts)
    # Check depth for flooded assets
    if len(flooded_gt) > 0:
        # Tolerance: +/- 0.1 ft
        flooded_gt['Peak_Depth_Above_Threshold_ft_agent'] = pd.to_numeric(flooded_gt['Peak_Depth_Above_Threshold_ft_agent'], errors='coerce').fillna(-999)
        
        depth_diff = np.abs(flooded_gt['Peak_Depth_Above_Threshold_ft_agent'] - flooded_gt['Peak_Depth_Above_Threshold_ft_truth'])
        depth_matches = depth_diff <= 0.1
        depth_score = (depth_matches.sum() / len(flooded_gt)) * 20
        score += depth_score
        feedback.append(f"Depth correct for {depth_matches.sum()}/{len(flooded_gt)} flooded assets.")
    else:
        score += 20

    # Criterion: Sorting (10 pts)
    # Check if 'Time_of_Onset_Hours' is monotonically increasing
    # Filter out NaNs (safe assets) which should be at the end
    try:
        # Get valid times
        times = pd.to_numeric(agent_df['Time_of_Onset_Hours'], errors='coerce')
        # Check if sorted (ignoring NaNs at end)
        valid_times = times.dropna()
        if valid_times.is_monotonic_increasing:
             # Check if NaNs are at the end (if any)
             last_valid_index = valid_times.index[-1] if len(valid_times) > 0 else -1
             first_nan_index = times[times.isna()].index[0] if times.isna().any() else len(times)
             
             if first_nan_index > last_valid_index:
                 score += 10
                 feedback.append("Sorting correct.")
             else:
                 feedback.append("Safe assets (NaN time) not listed last.")
        else:
            feedback.append("Timeline not sorted by onset time.")
    except Exception:
        feedback.append("Could not verify sorting.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }