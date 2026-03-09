#!/usr/bin/env python3
"""
Verifier for missing_value_configuration_toothgrowth task.

Verification Strategy:
1. Value Accuracy (40 pts): Checked 'corrected_mean.txt' against ground truth.
2. Configuration Check (40 pts): Inspects .omv file metadata to ensure -99 was set as missing.
3. File Artifacts (20 pts): OMV file exists and was created during task.
"""

import json
import os
import zipfile
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_missing_value_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Prepare temp files for extraction
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv').name
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Fetch JSON result
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # 2. Fetch Ground Truth
        try:
            copy_from_env("/tmp/ground_truth_mean.txt", temp_gt)
            with open(temp_gt, 'r') as f:
                ground_truth_mean = float(f.read().strip())
        except:
            # Fallback if file missing
            ground_truth_mean = 18.81  # Approximate fallback
            feedback_parts.append("(Using fallback ground truth)")

        # 3. Fetch User Report
        report_exists = result.get("report_exists", False)
        report_val = None
        if report_exists:
            try:
                copy_from_env("/tmp/result_report.txt", temp_report)
                with open(temp_report, 'r') as f:
                    content = f.read().strip()
                    # Extract number from string (e.g. "Mean: 18.8")
                    match = re.search(r"[-+]?\d*\.\d+|\d+", content)
                    if match:
                        report_val = float(match.group())
            except Exception as e:
                feedback_parts.append(f"Could not read report content: {e}")

        # --- SCORING CRITERION 1: Mean Value Accuracy (40 pts) ---
        if report_val is not None:
            diff = abs(report_val - ground_truth_mean)
            if diff < 0.05:
                score += 40
                feedback_parts.append(f"Correct mean reported ({report_val}).")
            elif diff < 0.5:
                score += 20
                feedback_parts.append(f"Mean slightly off (Expected {ground_truth_mean}, got {report_val}).")
            else:
                feedback_parts.append(f"Incorrect mean (Expected {ground_truth_mean}, got {report_val}).")
                if report_val < 0:
                    feedback_parts.append("Did you forget to handle the -99 values?")
        else:
            feedback_parts.append("No valid numeric mean reported.")

        # --- SCORING CRITERION 2: OMV Metadata Configuration (40 pts) ---
        omv_exists = result.get("omv_exists", False)
        missing_config_found = False
        
        if omv_exists:
            try:
                copy_from_env("/tmp/result_file.omv", temp_omv)
                if not zipfile.is_zipfile(temp_omv):
                    feedback_parts.append("OMV file is not a valid zip archive.")
                else:
                    with zipfile.ZipFile(temp_omv, 'r') as z:
                        # Scan for metadata JSON
                        # Jamovi structure varies but usually has metadata.json at root or in subfolder
                        meta_content = ""
                        for filename in z.namelist():
                            if filename.endswith(".json"):
                                try:
                                    content = z.read(filename).decode('utf-8', errors='ignore')
                                    # We look for the variable 'len' and its missingValues config
                                    # This is a heuristic search in the JSON string to be version-agnostic
                                    # Looking for something like: "name": "len" ... "missingValues": ["-99"]
                                    if '"len"' in content and '"missingValues"' in content:
                                        meta_content += content
                                except:
                                    continue
                        
                        # Check logic
                        # We specifically look for -99 in missing values context
                        # Simple regex check on the aggregate JSON content
                        if '-99' in meta_content and 'missingValues' in meta_content:
                            # A stronger check: look for sequence
                            # But since json key order isn't guaranteed, loose check is safer
                            missing_config_found = True
            except Exception as e:
                feedback_parts.append(f"Failed to inspect OMV file: {e}")

        if missing_config_found:
            score += 40
            feedback_parts.append("Missing value configuration confirmed in OMV file.")
        elif omv_exists:
            # If they got the right mean but we didn't find the config, they might have filtered/deleted rows
            # This is penalized because the task required configuration
            feedback_parts.append("Could not confirm missing value configuration in OMV metadata.")
        else:
            feedback_parts.append("OMV file not found.")

        # --- SCORING CRITERION 3: File Artifacts (20 pts) ---
        if omv_exists and result.get("omv_created_during_task", False):
            score += 20
            feedback_parts.append("Project file saved correctly.")
        elif omv_exists:
            score += 10
            feedback_parts.append("Project file exists but timestamp is suspicious.")
        
        # Penalize if they just deleted rows?
        # If mean is correct but config not found, score is max 40+20=60 (pass threshold is usually higher for perfect)
        # But let's say pass is 70. They fail if they don't configure.

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback_parts)
        }

    finally:
        # Cleanup
        for f in [temp_result_json, temp_omv, temp_report, temp_gt]:
            if os.path.exists(f):
                os.unlink(f)