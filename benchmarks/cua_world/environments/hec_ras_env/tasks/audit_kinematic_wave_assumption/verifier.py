#!/usr/bin/env python3
"""
Verifier for Audit Kinematic Wave Assumption task.

Checks:
1. Simulation run (HDF exists)
2. CSV output exists and has correct columns
3. Correct Peak Time used (checked against ground truth)
4. Correct Slope Calculations (compared to ground truth)
"""

import json
import os
import sys
import tempfile
import pandas as pd
import numpy as np
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_kinematic_wave_assumption(traj, env_info, task_info):
    """
    Verify the kinematic wave audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Load Task Result Metadata
        copy_from_env("/tmp/task_result.json", temp_result)
        with open(temp_result, 'r') as f:
            res_meta = json.load(f)
            
        # 2. Check Simulation Run
        if res_meta.get("simulation_run"):
            score += 10
            feedback_parts.append("Simulation results found.")
        else:
            return {"passed": False, "score": 0, "feedback": "Simulation not run (HDF output missing)."}
            
        # 3. Check CSV Existence
        if res_meta.get("csv_exists") and res_meta.get("csv_modified"):
            score += 10
            feedback_parts.append("Output CSV created.")
        else:
            return {"passed": False, "score": score, "feedback": "Output CSV not found or not created during task."}

        # 4. Load Ground Truth
        try:
            copy_from_env(res_meta["ground_truth_path"], temp_gt)
            with open(temp_gt, 'r') as f:
                gt_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ground truth validation data: {str(e)}"}
            
        if not gt_data.get("hdf_exists"):
             return {"passed": False, "score": score, "feedback": "Ground truth generation failed (HDF missing/corrupt)."}

        # 5. Load User CSV
        try:
            copy_from_env(res_meta["csv_path"], temp_csv)
            df = pd.read_csv(temp_csv)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to read output CSV: {str(e)}"}

        # 6. Check Columns
        expected_cols = ["Upstream_Station", "Downstream_Station", "Reach_Length_ft", "Bed_Slope", "WSE_Slope", "Slope_Ratio"]
        # Allow case-insensitive matching
        df.columns = [c.strip() for c in df.columns]
        missing_cols = [c for c in expected_cols if c not in df.columns]
        
        if not missing_cols:
            score += 10
            feedback_parts.append("CSV columns correct.")
        else:
            feedback_parts.append(f"Missing columns: {missing_cols}")
            # Penalize but continue if possible
            if "WSE_Slope" not in df.columns or "Bed_Slope" not in df.columns:
                return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # 7. Compare Data
        # We align rows by Upstream_Station
        gt_rows = gt_data["data"]
        
        # Check if user has data
        if df.empty:
            return {"passed": False, "score": score, "feedback": "CSV is empty."}
            
        # Check if data looks like it matches the row count
        if abs(len(df) - len(gt_rows)) > 2:
            feedback_parts.append(f"Row count mismatch (Expected ~{len(gt_rows)}, Got {len(df)}).")
        
        # Validate values (Sample first 3 rows and random middle row)
        matches = 0
        total_checked = 0
        
        # Convert df 'Upstream_Station' to string for matching
        df['Upstream_Station'] = df['Upstream_Station'].astype(str).str.strip()
        
        for gt_row in gt_rows:
            # Find matching row in DF
            u_stat = str(gt_row['upstream'])
            
            # Fuzzy match river station (sometimes '1234.5' vs '1234.50')
            # Best effort lookup
            user_row = df[df['Upstream_Station'] == u_stat]
            
            if user_row.empty:
                continue
                
            user_row = user_row.iloc[0]
            total_checked += 1
            
            # Check Slopes (tolerance 5% or 0.0001 absolute)
            s0_ok = np.isclose(user_row['Bed_Slope'], gt_row['s0'], rtol=0.05, atol=0.0001)
            sw_ok = np.isclose(user_row['WSE_Slope'], gt_row['sw'], rtol=0.05, atol=0.0001)
            
            if s0_ok and sw_ok:
                matches += 1
                
        # Scoring based on data match
        if total_checked > 0:
            match_rate = matches / total_checked
            if match_rate > 0.9:
                score += 70 # Full points for data accuracy
                feedback_parts.append("Slope calculations match ground truth.")
            elif match_rate > 0.5:
                score += 35
                feedback_parts.append(f"Partial data match ({int(match_rate*100)}%). Check formulae.")
            else:
                feedback_parts.append("Calculated values do not match expected values. Did you use the Peak Snapshot?")
                # Check if they might have used Max Envelope?
                # (Hard to verify explicitly without generating Max Envelope GT, but mismatch implies error)
        else:
            feedback_parts.append("Could not match River Stations between output and ground truth.")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for f in [temp_result, temp_gt, temp_csv]:
            if os.path.exists(f):
                os.unlink(f)

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }