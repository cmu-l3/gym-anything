#!/usr/bin/env python3
"""
Verifier for Clinical Data ETL Pipeline task.

Verification Strategy:
1. File Existence: Check if CSV exists and was created during the task.
2. Structure: Check for correct header and column format.
3. Content Matching (Anti-Gaming):
   - Compare the agent's CSV against a Ground Truth CSV generated from the actual logs.
   - We check if the values in the agent's CSV actually appear in the logs (Ground Truth).
   - This prevents the agent from submitting a pre-canned or random CSV.
   - We allow for some timestamp drift or format differences, but values must match specific simulated data points.

Scoring (100 pts):
- 20 pts: Data Generation (Evidence of devices in logs/system).
- 20 pts: CSV Structure (File exists, header correct).
- 20 pts: Heart Rate Data (Contains valid HR values matching logs).
- 20 pts: SpO2 Data (Contains valid SpO2 values matching logs).
- 20 pts: Volume (At least 30 rows of data).
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clinical_data_etl(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Artifacts
    temp_dir = tempfile.mkdtemp()
    try:
        # Load JSON result
        json_path = os.path.join(temp_dir, "task_result.json")
        copy_from_env("/tmp/task_result.json", json_path)
        with open(json_path, 'r') as f:
            result = json.load(f)
            
        # Load Agent CSV
        agent_csv_path = os.path.join(temp_dir, "agent.csv")
        try:
            copy_from_env("/tmp/agent_output.csv", agent_csv_path)
            agent_data_exists = True
        except:
            agent_data_exists = False
            
        # Load Ground Truth CSV
        gt_csv_path = os.path.join(temp_dir, "ground_truth.csv")
        try:
            copy_from_env("/tmp/ground_truth_extract.csv", gt_csv_path)
            gt_data_exists = True
        except:
            gt_data_exists = False

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}

    score = 0
    feedback = []

    # --- Criterion 1: Data Generation (20 pts) ---
    device_count = result.get("device_evidence_count", 0)
    # We also check if GT has data, implying simulation was running
    gt_rows = result.get("ground_truth_rows", 0)
    
    if device_count >= 1 or gt_rows > 5:
        score += 20
        feedback.append("Devices active and generating data.")
    else:
        feedback.append("No active devices or data generation detected.")

    # --- Criterion 2: CSV Structure (20 pts) ---
    csv_valid = False
    agent_rows = []
    
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        try:
            with open(agent_csv_path, 'r') as f:
                reader = csv.reader(f)
                header = next(reader, None)
                if header and len(header) >= 3 and \
                   "timestamp" in header[0].lower() and \
                   "metric" in header[1].lower() and \
                   "value" in header[2].lower():
                    score += 20
                    csv_valid = True
                    feedback.append("CSV created with correct header.")
                    for row in reader:
                        if len(row) >= 3:
                            agent_rows.append(row)
                else:
                    feedback.append("CSV header incorrect. Expected 'Timestamp,Metric,Value'.")
        except Exception as e:
            feedback.append(f"CSV format error: {str(e)}")
    else:
        feedback.append("CSV file not found or not created during task.")

    # --- Criterion 3 & 4: Data Content Matching (40 pts) ---
    # We build a set of (Metric, Value) pairs from Ground Truth to verify Agent's data
    gt_pairs = set()
    if gt_data_exists:
        with open(gt_csv_path, 'r') as f:
            reader = csv.reader(f)
            next(reader, None) # skip header
            for row in reader:
                if len(row) >= 3:
                    # (Metric, Value) - assume values are roughly strings "72" or "72.0"
                    # We strip decimals for integer comparison if needed, or exact string match
                    m = row[1].strip()
                    v = row[2].strip()
                    gt_pairs.add((m, v))
                    # Also add a float-normalized version
                    try:
                        gt_pairs.add((m, str(float(v))))
                        gt_pairs.add((m, str(int(float(v)))))
                    except:
                        pass

    matched_hr = 0
    matched_spo2 = 0
    
    if csv_valid and gt_pairs:
        for row in agent_rows:
            metric = row[1].strip()
            val = row[2].strip()
            
            # Normalize Metric Names
            if "heart" in metric.lower():
                norm_metric = "HeartRate"
            elif "spo2" in metric.lower() or "oxim" in metric.lower():
                norm_metric = "SpO2"
            else:
                norm_metric = metric

            # Check matching
            # We look for (NormMetric, Value) in GT
            # We check both exact NormMetric and raw Metric name from GT just in case
            match_found = False
            
            # Try direct lookup
            if (norm_metric, val) in gt_pairs:
                match_found = True
            
            # Try float normalized lookup
            try:
                if not match_found:
                    v_float = str(float(val))
                    if (norm_metric, v_float) in gt_pairs:
                        match_found = True
                    # Try int
                    v_int = str(int(float(val)))
                    if (norm_metric, v_int) in gt_pairs:
                        match_found = True
            except:
                pass

            if match_found:
                if norm_metric == "HeartRate": matched_hr += 1
                if norm_metric == "SpO2": matched_spo2 += 1

    # Score Content
    if matched_hr > 5:
        score += 20
        feedback.append(f"Verified {matched_hr} Heart Rate data points.")
    elif matched_hr > 0:
        score += 10
        feedback.append(f"Found some Heart Rate data ({matched_hr}), but low count.")
    else:
        feedback.append("No verified Heart Rate data found.")

    if matched_spo2 > 5:
        score += 20
        feedback.append(f"Verified {matched_spo2} SpO2 data points.")
    elif matched_spo2 > 0:
        score += 10
        feedback.append(f"Found some SpO2 data ({matched_spo2}), but low count.")
    else:
        feedback.append("No verified SpO2 data found.")

    # --- Criterion 5: Volume (20 pts) ---
    if len(agent_rows) >= 30:
        score += 20
        feedback.append(f"Volume check passed ({len(agent_rows)} rows).")
    elif len(agent_rows) > 0:
        score += 10
        feedback.append(f"Volume check partial ({len(agent_rows)} rows). Expected 30+.")
    else:
        feedback.append("File empty or parsing failed.")

    # Final Feedback
    if not gt_pairs and gt_data_exists:
        feedback.append("Warning: Ground Truth was empty. Simulator might not have logged data.")
        # If simulation failed to produce logs, we can't blame agent for not matching
        # But agent still gets points for Structure and Volume if they produced something plausible
        # This is an edge case.

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }