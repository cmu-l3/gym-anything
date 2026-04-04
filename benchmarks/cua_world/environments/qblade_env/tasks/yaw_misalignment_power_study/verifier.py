#!/usr/bin/env python3
"""
Verifier for yaw_misalignment_power_study task.

Criteria:
1. Project file exists and has content (10 pts)
2. Report file exists (10 pts)
3. Report contains valid CSV data with 4 rows (20 pts)
4. Power decreases as Yaw increases (Physics check) (30 pts)
5. Power at 0 deg is reasonable for NREL 5MW @ 11m/s (~4.5-5.5 MW) (15 pts)
6. Power at 30 deg shows significant loss relative to 0 deg (15 pts)
"""

import json
import os
import tempfile
import csv
import io
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_yaw_misalignment_power_study(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    metadata = task_info.get('metadata', {})
    report_path = metadata.get('report_path', '/home/ga/Documents/projects/yaw_power_report.csv')
    
    # 1. Get JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Project Saved (10 pts)
    if result.get('project_exists') and int(result.get('project_size', 0)) > 5000:
        score += 10
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file missing or empty")

    # Criterion 2: Report Exists (10 pts)
    if result.get('report_exists'):
        score += 10
        feedback_parts.append("Report file found")
    else:
        feedback_parts.append("Report file missing")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Parse Report Data
    # Copy the actual CSV file to ensure clean parsing, fallback to base64 from JSON if copy fails
    csv_content = ""
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(report_path, temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            csv_content = f.read()
    except Exception:
        # Fallback to base64 from json
        if result.get('report_content_b64'):
            try:
                csv_content = base64.b64decode(result.get('report_content_b64')).decode('utf-8')
            except:
                pass
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    data_points = []
    try:
        # Simple parser to handle potential header variations
        lines = csv_content.strip().split('\n')
        reader = csv.reader(lines)
        for row in reader:
            # Skip header if it contains text
            if len(row) >= 2 and not row[0].replace('.','',1).isdigit():
                continue
            if len(row) >= 2:
                try:
                    yaw = float(row[0])
                    power = float(row[1])
                    data_points.append((yaw, power))
                except ValueError:
                    continue
        
        # Sort by yaw just in case
        data_points.sort(key=lambda x: x[0])
        
    except Exception as e:
        feedback_parts.append(f"Failed to parse CSV: {str(e)}")

    # Criterion 3: Data Integrity (20 pts)
    if len(data_points) >= 4:
        score += 20
        feedback_parts.append(f"Found {len(data_points)} data points")
    else:
        feedback_parts.append(f"Found only {len(data_points)} data points (expected 4)")
        # If less than 2 points, cannot verify trends
        if len(data_points) < 2:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 4: Physics Validation - Monotonic Decrease (30 pts)
    # Check if Power(Yaw) > Power(Yaw+10)
    monotonic = True
    for i in range(len(data_points) - 1):
        if data_points[i][1] <= data_points[i+1][1]:
            monotonic = False
            break
    
    if monotonic and len(data_points) >= 3:
        score += 30
        feedback_parts.append("Power decreases with yaw (physics correct)")
    elif len(data_points) >= 3:
        feedback_parts.append("Power does not strictly decrease with yaw")
    else:
        feedback_parts.append("Insufficient data to verify trend")

    # Criterion 5: Accuracy at 0 deg (15 pts)
    # NREL 5MW at 11m/s should be near rated or high power. 
    # Rated is 5MW. At 11m/s it is slightly below rated (around 4.5-5.2MW depending on air density).
    # Let's accept 4000 to 5600 kW.
    p_zero = next((p for y, p in data_points if abs(y) < 1), None)
    
    if p_zero is not None:
        if 4000 <= p_zero <= 5600:
            score += 15
            feedback_parts.append(f"Aligned power reasonable ({p_zero:.1f} kW)")
        else:
            feedback_parts.append(f"Aligned power out of range ({p_zero:.1f} kW, exp ~5000)")
    else:
        feedback_parts.append("0-degree data point missing")

    # Criterion 6: Accuracy at 30 deg (15 pts)
    # Power drops by cos^k(yaw). cos(30) = 0.866. 0.866^2 = 0.75, 0.866^3 = 0.65.
    # So P_30 should be roughly 65-80% of P_0.
    p_thirty = next((p for y, p in data_points if abs(y - 30) < 1), None)
    
    if p_zero is not None and p_thirty is not None and p_zero > 0:
        ratio = p_thirty / p_zero
        if 0.5 <= ratio <= 0.92:
            score += 15
            feedback_parts.append(f"Yaw loss reasonable (ratio {ratio:.2f})")
        else:
            feedback_parts.append(f"Yaw loss ratio unexpected ({ratio:.2f})")
    else:
        feedback_parts.append("Cannot calculate yaw loss ratio")

    # Final result
    passed = score >= 60 and monotonic
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }