#!/usr/bin/env python3
"""
Verifier for benchmark_simulation_performance task.
Checks if HEC-RAS simulation was run, log captured, and performance metrics calculated correctly.
"""

import json
import os
import tempfile
import base64
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_benchmark_simulation_performance(traj, env_info, task_info):
    """
    Verify the HEC-RAS benchmark task.
    
    Criteria:
    1. Simulation Log Created (25 pts): File exists, created during task, contains RAS output.
    2. Benchmark Report Created (25 pts): CSV exists with correct headers.
    3. Simulated Duration Correct (20 pts): Matches expected range for Muncie (approx 16-48h).
    4. Speed Metric Calculated (20 pts): Ratio = Hours / Seconds (within 5% tolerance).
    5. Stability Check (10 pts): Warning count is a valid integer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Metadata
    metadata = task_info.get('metadata', {})
    min_sim_hours = metadata.get('min_simulated_hours', 1.0)
    max_sim_hours = metadata.get('max_simulated_hours', 200.0)

    # --- Criterion 1: Simulation Log (25 pts) ---
    log_exists = result.get('log_exists', False)
    log_created = result.get('log_created_during_task', False)
    log_head_b64 = result.get('log_content_head_b64', "")
    
    log_valid = False
    if log_exists and log_created:
        try:
            log_head = base64.b64decode(log_head_b64).decode('utf-8', errors='ignore')
            # Check for characteristic HEC-RAS output terms
            if "HEC-RAS" in log_head or "River Analysis System" in log_head or "Unsteady" in log_head or "Plan:" in log_head:
                score += 25
                log_valid = True
                feedback_parts.append("Simulation log created and valid.")
            else:
                score += 10 # File exists but content dubious
                feedback_parts.append("Log file created but does not look like HEC-RAS output.")
        except:
            feedback_parts.append("Log file created but content unreadable.")
    else:
        feedback_parts.append("Simulation log missing or not created during task.")

    # --- Criterion 2: Benchmark Report Existence & Format (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    report_content_b64 = result.get('report_content_b64', "")
    
    report_data = None
    
    if report_exists and report_created:
        try:
            report_str = base64.b64decode(report_content_b64).decode('utf-8', errors='ignore')
            f = io.StringIO(report_str)
            reader = csv.DictReader(f)
            rows = list(reader)
            
            if len(rows) > 0:
                headers = reader.fieldnames
                required_headers = ["WallClockSeconds", "SimulatedHours", "PerformanceRatio_HrPerSec", "ConvergenceWarnings", "LogFileSize_Bytes"]
                
                # Check headers (case insensitive/stripped)
                normalized_headers = [h.strip() for h in headers] if headers else []
                missing = [h for h in required_headers if h not in normalized_headers]
                
                if not missing:
                    score += 25
                    report_data = rows[0] # Take first row
                    feedback_parts.append("Benchmark report format correct.")
                else:
                    score += 10
                    feedback_parts.append(f"Benchmark report missing columns: {missing}")
            else:
                feedback_parts.append("Benchmark report is empty.")
        except Exception as e:
            feedback_parts.append(f"Failed to parse CSV: {e}")
    else:
        feedback_parts.append("Benchmark report missing.")

    # --- Data Verification ---
    if report_data:
        try:
            wc_sec = float(report_data.get("WallClockSeconds", 0))
            sim_hrs = float(report_data.get("SimulatedHours", 0))
            ratio = float(report_data.get("PerformanceRatio_HrPerSec", 0))
            warnings = int(report_data.get("ConvergenceWarnings", -1))
            
            # Criterion 3: Simulated Duration (20 pts)
            if min_sim_hours <= sim_hrs <= max_sim_hours:
                score += 20
                feedback_parts.append(f"Simulated duration ({sim_hrs}h) within expected range.")
            else:
                feedback_parts.append(f"Simulated duration ({sim_hrs}h) outside range [{min_sim_hours}, {max_sim_hours}].")

            # Criterion 4: Math Check (20 pts)
            # Avoid division by zero
            if wc_sec > 0:
                calc_ratio = sim_hrs / wc_sec
                # Allow 5% tolerance or 0.01 absolute
                if abs(calc_ratio - ratio) < (0.05 * calc_ratio) + 0.01:
                    score += 20
                    feedback_parts.append("Performance ratio calculated correctly.")
                else:
                    feedback_parts.append(f"Performance ratio mismatch (Reported: {ratio}, Calc: {calc_ratio:.4f}).")
            else:
                feedback_parts.append("Wall clock seconds is zero or negative.")

            # Criterion 5: Stability Check (10 pts)
            if warnings >= 0:
                score += 10
                feedback_parts.append(f"Convergence warnings check passed (Count: {warnings}).")
            else:
                feedback_parts.append("Invalid warning count.")
                
        except ValueError:
            feedback_parts.append("Non-numeric data in report.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }