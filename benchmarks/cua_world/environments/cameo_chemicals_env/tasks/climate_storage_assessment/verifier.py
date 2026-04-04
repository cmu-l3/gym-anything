#!/usr/bin/env python3
"""
Verifier for Climate Storage Assessment task.
Checks the generated CSV file for correct physical property extraction and logic application.
"""

import json
import csv
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_climate_storage_assessment(traj, env_info, task_info):
    """
    Verifies the CSV output for the climate storage assessment.
    
    Scoring Breakdown:
    - 10 pts: CSV file exists and is readable
    - 30 pts: Data Accuracy (Melting/Boiling points within tolerance)
    - 60 pts: Logic Classification (Correct Action assigned)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/shipping_manifest.csv')

    # Temporary files for extraction
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Check metadata from export script
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            meta_result = json.load(f)
            
        if not meta_result.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}
            
        if not meta_result.get('file_created_during_task', False):
            return {"passed": False, "score": 0, "feedback": "Output file exists but was not created during this task (stale data)."}

        # 2. Parse CSV Content
        try:
            copy_from_env(output_path, temp_csv.name)
            with open(temp_csv.name, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"File exists but is not valid CSV: {str(e)}"}

        if not rows:
            return {"passed": False, "score": 10, "feedback": "CSV file is empty."}
            
        score += 10 # CSV exists and is readable
        
        # 3. Validate Data
        data_points_score = 0
        logic_score = 0
        max_data_points = 30
        max_logic = 60
        
        chemicals_found = 0
        
        # Normalization helper
        def normalize_name(name):
            return name.lower().replace("-", "").replace(" ", "").strip()

        # Map ground truth keys for easy lookup
        gt_lookup = {normalize_name(k): v for k, v in ground_truth.items()}
        
        # Tolerance for temperature values (different sources might vary slightly)
        TEMP_TOLERANCE = 5.0 

        for row in rows:
            # Extract row data
            chem_name = row.get('Chemical', '').strip()
            # Try to get MP/BP, handling potential empty strings or parsing errors
            try:
                mp_val = float(row.get('Melting Point (F)', -9999))
            except (ValueError, TypeError):
                mp_val = None
                
            try:
                bp_val = float(row.get('Boiling Point (F)', -9999))
            except (ValueError, TypeError):
                bp_val = None
                
            action = row.get('Action', '').upper().strip()
            
            # Find matching ground truth
            norm_name = normalize_name(chem_name)
            if norm_name in gt_lookup:
                gt = gt_lookup[norm_name]
                chemicals_found += 1
                
                # Check MP Accuracy (2.5 pts)
                mp_correct = False
                if mp_val is not None and abs(mp_val - gt['mp']) <= TEMP_TOLERANCE:
                    data_points_score += 2.5
                    mp_correct = True
                
                # Check BP Accuracy (2.5 pts)
                bp_correct = False
                if bp_val is not None and abs(bp_val - gt['bp']) <= TEMP_TOLERANCE:
                    data_points_score += 2.5
                    bp_correct = True
                    
                # Check Logic (10 pts)
                # We award points if the Action matches Ground Truth Action
                # OR if the Action is logically consistent with the agent's provided (valid) values
                # But to enforce strict standards, we usually demand correctness against GT.
                if action == gt['action']:
                    logic_score += 10
                else:
                    feedback_parts.append(f"Wrong action for {chem_name}: Expected {gt['action']}, got {action}")

        score += data_points_score + logic_score
        
        if chemicals_found < 6:
            feedback_parts.append(f"Only found {chemicals_found}/6 chemicals in CSV.")
            
        if data_points_score < max_data_points:
            feedback_parts.append("Some temperature values were inaccurate.")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Optional VLM Sanity Check (Trajectory Analysis)
    # Check if they actually visited CAMEO Chemicals
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    if frames and query_vlm:
        vlm_res = query_vlm(
            images=frames + [final_img],
            prompt="Does the user visit the CAMEO Chemicals website and look at chemical properties?"
        )
        if not vlm_res.get('passed', True) and "no" in vlm_res.get('response', '').lower():
             feedback_parts.append("VLM did not detect CAMEO Chemicals usage.")
             # We don't deduct points here to avoid false negatives, but could use for debugging.

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": round(score),
        "feedback": " | ".join(feedback_parts) if feedback_parts else "All data and logic correct."
    }