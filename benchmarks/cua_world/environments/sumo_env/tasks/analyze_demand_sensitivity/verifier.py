#!/usr/bin/env python3
"""
Verifier for analyze_demand_sensitivity task.

Verification Criteria:
1. File Generation (20 pts) - All 5 XML stat files generated.
2. Scaling Execution (20 pts) - Vehicle counts show deterministic progression proving --scale worked.
3. CSV Formatting (10 pts) - CSV exists with exactly correct headers.
4. Data Accuracy (30 pts) - Parsed CSV matches the XML timeLoss values generated (anti-hallucination).
5. Logical Trend (20 pts) - timeLoss strictly increased from 0.8 to 1.2 scales.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_demand_sensitivity(traj, env_info, task_info):
    """Verify that demand sensitivity sweep was correctly executed and reported."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    scales = ["0.8", "0.9", "1.0", "1.1", "1.2"]

    xml_data = result.get("xml_data", {})
    csv_exists = result.get("csv_exists", False)
    csv_headers = result.get("csv_headers", [])
    csv_data = result.get("csv_data", {})

    # Criterion 1: File Generation (20 pts)
    valid_xmls = 0
    for scale in scales:
        if scale in xml_data and "error" not in xml_data[scale]:
            valid_xmls += 1
            
    if valid_xmls == 5:
        score += 20
        feedback_parts.append("All 5 stats XML files generated successfully.")
    else:
        feedback_parts.append(f"Only {valid_xmls}/5 stats XML files generated/valid.")

    # Criterion 2: Scaling Execution (20 pts)
    # Check if the scale parameter actually changed simulation volume
    counts = [xml_data.get(s, {}).get("count", 0) for s in scales]
    if valid_xmls == 5 and all(counts[i] < counts[i+1] for i in range(len(counts)-1)):
        score += 20
        feedback_parts.append("Vehicle counts strictly increase with scale, proving --scale worked.")
    else:
        feedback_parts.append("Vehicle counts did not strictly increase; scaling command failed.")

    # Criterion 3: CSV Formatting (10 pts)
    if csv_exists:
        if len(csv_headers) == 2 and csv_headers[0] == "Scale" and csv_headers[1] == "Average_TimeLoss":
            score += 10
            feedback_parts.append("CSV formatting and headers are correct.")
        else:
            feedback_parts.append(f"CSV headers incorrect. Expected ['Scale', 'Average_TimeLoss'], got {csv_headers}")
    else:
        feedback_parts.append("CSV file 'demand_sensitivity.csv' not found.")

    # Criterion 4: Data Accuracy (30 pts)
    accuracy_score = 0
    matches = 0
    if csv_exists and valid_xmls == 5:
        for scale in scales:
            expected_val = xml_data[scale].get("timeLoss")
            actual_val = csv_data.get(scale)
            
            if actual_val is not None and expected_val is not None:
                # 0.05 tolerance for minor rounding variations
                if abs(actual_val - expected_val) <= 0.05:
                    matches += 1

        if matches == 5:
            score += 30
            accuracy_score = 30
            feedback_parts.append("Data accuracy: All CSV values perfectly match extracted XML timeLoss.")
        else:
            feedback_parts.append(f"Data accuracy: Only {matches}/5 values matched between CSV and true XML outputs.")
    else:
        feedback_parts.append("Data accuracy: Cannot check due to missing files or data.")

    # Criterion 5: Logical Trend Validation (20 pts)
    if valid_xmls == 5:
        tl_08 = xml_data["0.8"].get("timeLoss", 0)
        tl_12 = xml_data["1.2"].get("timeLoss", 0)
        if tl_12 > tl_08:
            score += 20
            feedback_parts.append("Logical trend: Time loss correctly increases with higher demand.")
        else:
            feedback_parts.append(f"Logical trend failed: Time loss at 1.2 ({tl_12}) not greater than at 0.8 ({tl_08}).")

    # Pass condition: must score at least 80 AND pass the Data Accuracy check entirely (anti-gaming feature)
    passed = score >= 80 and accuracy_score == 30
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }