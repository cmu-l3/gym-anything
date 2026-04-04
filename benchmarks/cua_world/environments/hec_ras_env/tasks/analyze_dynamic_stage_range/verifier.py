#!/usr/bin/env python3
"""
Verifier for analyze_dynamic_stage_range task.
"""

import json
import tempfile
import os
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_dynamic_stage_range(traj, env_info, task_info):
    """
    Verify the HEC-RAS dynamic stage range analysis.
    
    Criteria:
    1. Output CSV exists and was created during task.
    2. Numerical accuracy: CSV values match ground truth (generated from HDF5).
    3. Critical station identification: Text file matches calculated max range station.
    4. Plot existence and validity: PNG created and reasonable size.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load Task Result Metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)

    # 2. Load Ground Truth (Generated in export_result.sh)
    gt_data = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception:
        # If ground truth failed to generate, we can't fully verify numerical accuracy
        logger.warning("Ground truth file missing or invalid.")
        gt_data = {"status": "missing"}
    finally:
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    # --- Scoring ---

    # Criterion 1: CSV Existence (20 pts)
    if task_result.get("csv_exists") and task_result.get("csv_created_during_task"):
        score += 20
        feedback_parts.append("CSV summary created")
    else:
        feedback_parts.append("CSV summary missing or not created during task")

    # Criterion 2: Numerical Accuracy (40 pts)
    # Compare agent CSV against Ground Truth samples
    accuracy_passed = False
    if task_result.get("csv_exists") and gt_data.get("status") == "success":
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/agent_summary.csv", temp_csv.name)
            
            # Read Agent CSV
            agent_rows = {}
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                # Normalize column names (strip spaces, lower case)
                reader.fieldnames = [name.strip() for name in reader.fieldnames]
                for row in reader:
                    # Find station column
                    station_key = next((k for k in row.keys() if 'station' in k.lower()), None)
                    if station_key:
                        agent_rows[row[station_key].strip()] = row
            
            # Verify Samples
            samples = gt_data.get("samples", [])
            matches = 0
            for sample in samples:
                station = sample["station"]
                if station in agent_rows:
                    row = agent_rows[station]
                    # Check Range
                    range_key = next((k for k in row.keys() if 'range' in k.lower() or 'fluc' in k.lower()), None)
                    if range_key:
                        try:
                            agent_val = float(row[range_key])
                            gt_val = sample["range"]
                            if math.isclose(agent_val, gt_val, abs_tol=0.05):
                                matches += 1
                        except ValueError:
                            pass
            
            if matches >= len(samples) - 1 and len(samples) > 0:
                score += 40
                accuracy_passed = True
                feedback_parts.append("Data values accurate")
            elif matches > 0:
                score += 20
                feedback_parts.append("Data values partially accurate")
            else:
                feedback_parts.append("Data values mismatch")

        except Exception as e:
            feedback_parts.append(f"Failed to verify CSV content: {e}")
        finally:
            if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)
    elif gt_data.get("status") != "success":
        feedback_parts.append("Skipping numerical verification (Ground Truth generation failed)")
        # Fallback points if GT failed but file exists (system error benefit of doubt)
        if task_result.get("csv_exists"): score += 20

    # Criterion 3: Critical Station ID (20 pts)
    if task_result.get("txt_exists") and gt_data.get("status") == "success":
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/agent_location.txt", temp_txt.name)
            with open(temp_txt.name, 'r') as f:
                content = f.read()
            
            expected_station = str(gt_data.get("critical_station"))
            if expected_station in content:
                score += 20
                feedback_parts.append(f"Correct critical station identified ({expected_station})")
            else:
                feedback_parts.append(f"Incorrect critical station (Expected {expected_station})")
        finally:
            if os.path.exists(temp_txt.name): os.unlink(temp_txt.name)

    # Criterion 4: Plot Generation (20 pts)
    if task_result.get("plot_exists"):
        plot_size = task_result.get("plot_size", 0)
        if plot_size > 5000: # Arbitrary small check for non-empty file
            score += 20
            feedback_parts.append("Profile plot generated")
        else:
            score += 5
            feedback_parts.append("Plot file exists but seems empty/small")

    # Pass Threshold
    # Must have CSV and reasonable accuracy OR perfect structure
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }