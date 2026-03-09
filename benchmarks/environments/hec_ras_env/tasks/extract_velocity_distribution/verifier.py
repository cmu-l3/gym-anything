#!/usr/bin/env python3
"""
Verifier for extract_velocity_distribution task.
"""

import json
import os
import tempfile
import csv
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_velocity_distribution(traj, env_info, task_info):
    """
    Verify the velocity distribution extraction task.
    
    Checks:
    1. CSV file exists and was created during task (20 pts)
    2. CSV structure is valid (headers) (15 pts)
    3. CSV content is reasonable (rows >= 5, positive velocities) (15 pts)
    4. Summary file exists and matches CSV peak (25 pts)
    5. VLM verification of workflow (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('expected_csv_path')
    expected_summary_path = metadata.get('expected_summary_path')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            task_result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # 2. Check CSV existence and timestamp (20 pts)
    if task_result.get("csv_exists") and task_result.get("csv_created_during_task"):
        score += 20
        feedback_parts.append("CSV file created successfully")
    elif task_result.get("csv_exists"):
        score += 5
        feedback_parts.append("CSV file exists but timestamp check failed")
    else:
        feedback_parts.append("CSV file NOT found")

    # 3. Analyze CSV Content (30 pts total)
    csv_valid = False
    csv_peak_value = -1.0
    
    if task_result.get("csv_exists"):
        with tempfile.NamedTemporaryFile(suffix='.csv') as tf:
            try:
                copy_from_env(expected_csv_path, tf.name)
                tf.seek(0)
                
                # Check headers (15 pts)
                with open(tf.name, 'r') as f:
                    reader = csv.DictReader(f)
                    headers = [h.strip().lower() for h in reader.fieldnames or []]
                    
                    required = ["cross_section", "max_velocity", "mean_velocity", "min_velocity"]
                    missing = [r for r in required if not any(r in h for h in headers)]
                    
                    if not missing:
                        score += 15
                        feedback_parts.append("CSV headers correct")
                        
                        # Check Data Rows (15 pts)
                        rows = list(reader)
                        if len(rows) >= 5:
                            # Check values
                            valid_values = True
                            max_vals = []
                            for row in rows:
                                try:
                                    # Find the key that corresponds to max_velocity
                                    max_key = next(k for k in row.keys() if "max" in k.lower() and "vel" in k.lower())
                                    val = float(row[max_key])
                                    max_vals.append(val)
                                    if val < 0 or val > 30: # 30 ft/s is very high for Muncie
                                        valid_values = False
                                except:
                                    valid_values = False
                            
                            if valid_values and max_vals:
                                score += 15
                                csv_peak_value = max(max_vals)
                                csv_valid = True
                                feedback_parts.append(f"CSV data valid (n={len(rows)})")
                            else:
                                feedback_parts.append("CSV contains invalid/unreasonable values")
                        else:
                            feedback_parts.append(f"CSV has too few rows ({len(rows)})")
                    else:
                        feedback_parts.append(f"Missing CSV headers: {missing}")
            except Exception as e:
                feedback_parts.append(f"Failed to parse CSV: {e}")

    # 4. Check Summary File Consistency (25 pts)
    if task_result.get("summary_exists"):
        with tempfile.NamedTemporaryFile(suffix='.txt') as tf:
            try:
                copy_from_env(expected_summary_path, tf.name)
                with open(tf.name, 'r') as f:
                    content = f.read().strip()
                
                if content:
                    # Try to extract number
                    import re
                    numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
                    found_match = False
                    if numbers and csv_peak_value > 0:
                        for num in numbers:
                            if abs(float(num) - csv_peak_value) < 0.1: # Tolerance
                                found_match = True
                                break
                    
                    if found_match:
                        score += 25
                        feedback_parts.append("Summary matches CSV data")
                    else:
                        score += 10 # Credit for creating file
                        feedback_parts.append(f"Summary value mismatch (CSV peak: {csv_peak_value})")
                else:
                    feedback_parts.append("Summary file empty")
            except Exception as e:
                feedback_parts.append(f"Failed to read summary: {e}")
    else:
        feedback_parts.append("Summary file NOT found")

    # 5. VLM Verification (25 pts)
    # Use trajectory frames to verify Python scripting and HDF exploration
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from an engineering task.
    The user is supposed to:
    1. Write/Run a Python script to analyze an HDF5 file.
    2. Extract velocity data.
    3. Save a CSV.
    
    Look for:
    - Terminal windows with Python code or execution.
    - Usage of 'h5py' or 'rashdf' libraries.
    - Printing of HDF5 structures (Groups/Datasets).
    - A CSV file or text editor showing data output.
    
    Does the trajectory show evidence of programmatic data extraction?
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        if vlm_result.get("success"):
            # Simple heuristic: if VLM is positive, give points
            # In a real implementation, we'd parse the VLM's boolean/confidence
            # For this template, we'll assume a 'yes' in the response text is good
            response_text = vlm_result.get("text", "").lower()
            if "yes" in response_text or "evidence" in response_text:
                score += 25
                feedback_parts.append("VLM verified programmatic workflow")
            else:
                score += 10 # Partial credit if ambiguous
                feedback_parts.append("VLM analysis inconclusive")
        else:
            feedback_parts.append("VLM query failed")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: check for script files
        if task_result.get("agent_scripts_count", 0) > 0:
            score += 25
            feedback_parts.append("Python scripts detected (fallback verification)")

    return {
        "passed": score >= 70 and csv_valid,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }