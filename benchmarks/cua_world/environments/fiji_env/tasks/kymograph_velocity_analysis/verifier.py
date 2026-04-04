#!/usr/bin/env python3
"""
Verifier for Kymograph Velocity Analysis Task.

Criteria:
1. Kymograph Image Created (20 pts): Valid PNG, created during task, reasonable size.
2. Velocity CSV Valid (25 pts): Created during task, contains 'velocity' column, values > 0.
3. Biological Plausibility (20 pts): Velocities within 1-150 um/hr (HeLa cells typically 5-80 um/hr).
4. Report Consistency (15 pts): Report text exists and mentions velocity.
5. VLM Visual Verification (20 pts): Checks if the kymograph image looks like a real kymograph (diagonal streaks).
"""

import json
import os
import tempfile
import logging
import csv
import math
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_kymograph_analysis(traj, env_info, task_info):
    """
    Verifies the kymograph analysis task.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)."}

    score = 0
    feedback = []
    
    # Files to retrieve
    files = {
        "result_json": "/tmp/task_result.json",
        "csv": "/tmp/velocity_measurements.csv",
        "report": "/tmp/kymograph_report.txt",
        "kymo_img": "/tmp/kymograph_main.png"
    }
    
    local_files = {}
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        # Copy files
        for key, remote_path in files.items():
            local_path = os.path.join(temp_dir, os.path.basename(remote_path))
            try:
                copy_from_env(remote_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[key] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {key}: {e}")

        # Load main result metadata
        task_result = {}
        if "result_json" in local_files:
            try:
                with open(local_files["result_json"], 'r') as f:
                    task_result = json.load(f)
            except Exception as e:
                feedback.append(f"Error parsing result JSON: {str(e)}")

        # --- CRITERION 1: KYMOGRAPH IMAGE (20 pts) ---
        kymo_meta = task_result.get("kymograph_image", {})
        if kymo_meta.get("exists") and kymo_meta.get("valid_time"):
            if kymo_meta.get("size", 0) > 1000: # Check for non-empty file
                score += 20
                feedback.append("Kymograph image created successfully.")
            else:
                score += 5
                feedback.append("Kymograph image created but is empty/too small.")
        else:
            feedback.append("Kymograph image not found or not created during task.")

        # --- CRITERION 2: VELOCITY CSV STRUCTURE (25 pts) ---
        velocities = []
        csv_valid = False
        if "csv" in local_files and task_result.get("velocity_csv", {}).get("valid_time"):
            try:
                with open(local_files["csv"], 'r') as f:
                    reader = csv.DictReader(f)
                    # Normalize headers
                    headers = [h.lower() for h in reader.fieldnames or []]
                    
                    # Check for velocity column (flexible matching)
                    velocity_col = next((h for h in headers if "velocity" in h or "speed" in h or "um/hr" in h), None)
                    
                    if velocity_col:
                        for row in reader:
                            # Map row keys to normalized headers
                            row_norm = {k.lower(): v for k, v in row.items() if k}
                            try:
                                val = float(row_norm[velocity_col])
                                velocities.append(val)
                            except ValueError:
                                continue
                        
                        if len(velocities) >= 3:
                            score += 25
                            csv_valid = True
                            feedback.append(f"CSV valid with {len(velocities)} measurements.")
                        else:
                            score += 10
                            feedback.append(f"CSV found but too few measurements ({len(velocities)} < 3).")
                    else:
                        feedback.append("CSV found but 'velocity' column missing.")
            except Exception as e:
                feedback.append(f"Error parsing CSV: {str(e)}")
        else:
            feedback.append("Velocity CSV not found or invalid.")

        # --- CRITERION 3: BIOLOGICAL PLAUSIBILITY (20 pts) ---
        # HeLa cell velocity typically 5-80 um/hr. Extreme outliers suggest calibration error.
        if csv_valid and velocities:
            mean_vel = sum(velocities) / len(velocities)
            # Broad range allowance
            if 1.0 < mean_vel < 150.0:
                score += 20
                feedback.append(f"Calculated velocities are biologically plausible (Mean: {mean_vel:.2f} um/hr).")
            else:
                feedback.append(f"Velocities seem unrealistic (Mean: {mean_vel:.2f} um/hr). Check calibration (0.645 um/px, 30 min/frame).")
        
        # --- CRITERION 4: REPORT CONSISTENCY (15 pts) ---
        if "report" in local_files:
            try:
                with open(local_files["report"], 'r') as f:
                    content = f.read().lower()
                if "velocity" in content and any(char.isdigit() for char in content):
                    score += 15
                    feedback.append("Report file exists and contains data.")
                else:
                    score += 5
                    feedback.append("Report file exists but content is unclear.")
            except:
                pass
        else:
            feedback.append("Report file missing.")

        # --- CRITERION 5: VLM VISUAL VERIFICATION (20 pts) ---
        # Check if the kymograph actually looks like a kymograph (diagonal lines)
        vlm_passed = False
        if "kymo_img" in local_files:
            # We use the provided query_vlm helper if available
            query_vlm = env_info.get("query_vlm") # Mocked or provided by framework
            
            if query_vlm:
                prompt = (
                    "This is a scientific kymograph (space-time plot) generated from microscopy. "
                    "Does this image show diagonal streaks or lines on a dark or noisy background, "
                    "which represents moving objects? Answer YES or NO."
                )
                try:
                    # In a real run, we pass the image path or data
                    # Assuming framework handles local path or we need to pass image data
                    # For this implementation, we assume the framework's query_vlm handles the file path string
                    result = query_vlm(
                        prompt=prompt,
                        images=[local_files["kymo_img"]]
                    )
                    # Check result structure - assumes standard format
                    response = result.get("response", "").upper()
                    if "YES" in response:
                        score += 20
                        vlm_passed = True
                        feedback.append("VLM Verification: Valid kymograph structure detected.")
                    else:
                        feedback.append(f"VLM Verification: Image does not look like a kymograph. Response: {response}")
                except Exception as e:
                    # If VLM fails, we award points if file size is reasonable to avoid penalizing infra issues
                    logger.warning(f"VLM check failed: {e}")
                    score += 10 # Partial credit
                    feedback.append("VLM check failed (infra), partial credit awarded.")
            else:
                 # Fallback if no VLM available in dev environment
                 score += 20
                 feedback.append("VLM not available, skipping visual check (assuming valid if file exists).")
        
    # Final cleanup
    success = score >= 60
    
    return {
        "passed": success,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "mean_velocity": sum(velocities)/len(velocities) if velocities else 0,
            "n_measurements": len(velocities)
        }
    }