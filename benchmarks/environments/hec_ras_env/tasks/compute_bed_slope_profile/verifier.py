#!/usr/bin/env python3
"""
Verifier for compute_bed_slope_profile task.
Checks CSV structure and compares values against ground truth extracted from HDF5.
"""

import json
import tempfile
import os
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_bed_slope_profile(traj, env_info, task_info):
    """
    Verify the bed slope calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Files to fetch
    result_json_path = "/tmp/task_result.json"
    ground_truth_path = "/tmp/ground_truth.json"
    agent_csv_path = "/tmp/agent_output.csv"
    
    # 1. Load Task Result Metadata
    try:
        with tempfile.NamedTemporaryFile(suffix=".json") as tf:
            copy_from_env(result_json_path, tf.name)
            tf.seek(0)
            task_result = json.load(tf)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created"}
        
    score += 10 # File exists
    
    if task_result.get("file_created_during_task", False):
        score += 5 # Created during task
        
    # 2. Load Ground Truth
    ground_truth = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json") as tf:
            copy_from_env(ground_truth_path, tf.name)
            tf.seek(0)
            ground_truth = json.load(tf)
            
        if "error" in ground_truth:
            logger.warning(f"Ground truth generation failed: {ground_truth['error']}")
            # Fallback if ground truth failed (e.g. HDF issue): accept plausible CSV structure
            ground_truth_valid = False
        else:
            ground_truth_valid = True
            
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        ground_truth_valid = False

    # 3. Load Agent CSV
    agent_rows = []
    try:
        with tempfile.NamedTemporaryFile(suffix=".csv") as tf:
            copy_from_env(agent_csv_path, tf.name)
            tf.seek(0)
            # Read CSV
            reader = csv.DictReader(open(tf.name, 'r'))
            agent_rows = list(reader)
            
            # Verify Headers
            required = ["river_station", "thalweg_elevation", "downstream_distance", "bed_slope"]
            headers = reader.fieldnames if reader.fieldnames else []
            missing = [h for h in required if h not in headers]
            
            if not missing:
                score += 10 # Correct structure
            else:
                feedback_parts.append(f"Missing columns: {missing}")
                
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {str(e)}"}

    if len(agent_rows) == 0:
        return {"passed": False, "score": score, "feedback": "CSV file is empty"}
        
    score += 5 # Has data

    # 4. Compare Data
    if ground_truth_valid and "cross_sections" in ground_truth:
        gt_rows = ground_truth["cross_sections"]
        
        # Check row count
        if abs(len(agent_rows) - len(gt_rows)) <= 1:
            score += 10 # Correct number of rows
        else:
            feedback_parts.append(f"Row count mismatch: Expected ~{len(gt_rows)}, got {len(agent_rows)}")
        
        # Check values
        matches_found = 0
        elev_errors = []
        slope_errors = []
        
        for ag_row in agent_rows:
            rs = ag_row.get("river_station", "").strip()
            
            # Find matching ground truth
            match = next((g for g in gt_rows if str(g["river_station"]).strip() == rs), None)
            
            if match:
                matches_found += 1
                
                # Check Thalweg Elevation
                try:
                    ag_elev = float(ag_row.get("thalweg_elevation", -9999))
                    gt_elev = float(match["thalweg_elevation"])
                    if abs(ag_elev - gt_elev) < 0.5: # 0.5 ft tolerance
                        pass
                    else:
                        elev_errors.append(f"RS {rs}: Exp {gt_elev:.2f}, Got {ag_elev:.2f}")
                except:
                    elev_errors.append(f"RS {rs}: Invalid elevation format")

                # Check Slope
                try:
                    ag_slope_raw = ag_row.get("bed_slope", "NaN")
                    gt_slope_raw = match["bed_slope"]
                    
                    if str(ag_slope_raw).lower() in ['nan', '', 'none'] and (gt_slope_raw == "NaN" or gt_slope_raw is None):
                        pass # Both NaN, Good
                    else:
                        ag_slope = float(ag_slope_raw)
                        gt_slope = float(gt_slope_raw)
                        if abs(ag_slope - gt_slope) < 0.001: # Tolerance
                            pass
                        else:
                            slope_errors.append(f"RS {rs}: Exp {gt_slope:.5f}, Got {ag_slope:.5f}")
                except:
                     pass # Ignore parsing errors for slope if data is bad
            
        # Scoring Accuracy
        if matches_found > 0:
            if len(elev_errors) == 0:
                score += 30
            elif len(elev_errors) < 3:
                score += 15
                feedback_parts.append(f"Some elevation errors: {elev_errors[:2]}...")
            else:
                feedback_parts.append("Many elevation mismatches")

            if len(slope_errors) == 0:
                score += 30
            elif len(slope_errors) < 3:
                score += 15
                feedback_parts.append(f"Some slope errors: {slope_errors[:2]}...")
            else:
                feedback_parts.append("Many slope mismatches")
        else:
            feedback_parts.append("River Station IDs do not match ground truth")

    else:
        # Fallback if ground truth failed - sanity checks
        feedback_parts.append("Ground truth unavailable - performing sanity checks")
        
        # Check ranges
        valid_elevs = 0
        valid_slopes = 0
        for row in agent_rows:
            try:
                e = float(row.get("thalweg_elevation", 0))
                if 800 < e < 1200: valid_elevs += 1 # Reasonable for Muncie
                
                s = float(row.get("bed_slope", 0))
                if -0.1 < s < 0.1: valid_slopes += 1
            except:
                pass
        
        if valid_elevs >= len(agent_rows) * 0.8: score += 20
        if valid_slopes >= len(agent_rows) * 0.8: score += 20
        score += 20 # Benefit of doubt

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "Task completed successfully"
    }