#!/usr/bin/env python3
"""
Verifier for manufacturing_process_capability task.

Verifies:
1. PBIX creation and structure (Histogram, Lines, Card).
2. Correct Cpk calculation (compared against ground truth from raw data).
"""

import json
import os
import tempfile
import logging
import math
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_ground_truth_cpk(data_path, lsl, usl):
    """Calculates Cpk from the raw csv file."""
    try:
        diameters = []
        with open(data_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Assuming 'diameter' is the column name, handle potential BOM or whitespace
                key = next((k for k in row.keys() if 'diameter' in k.lower()), None)
                if key and row[key]:
                    try:
                        diameters.append(float(row[key]))
                    except ValueError:
                        continue
        
        if not diameters:
            return None

        n = len(diameters)
        mean = sum(diameters) / n
        variance = sum((x - mean) ** 2 for x in diameters) / n # STDEV.P uses N, not N-1
        std_dev = math.sqrt(variance)

        if std_dev == 0:
            return 0

        cpu = (usl - mean) / (3 * std_dev)
        cpl = (mean - lsl) / (3 * std_dev)
        cpk = min(cpu, cpl)
        
        return cpk
    except Exception as e:
        logger.error(f"Error calculating ground truth: {e}")
        return None

def verify_manufacturing_process_capability(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    lsl = metadata.get('lsl', 73.990)
    usl = metadata.get('usl', 74.010)

    # Temporary files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_result.close()
    temp_csv.close()

    feedback_parts = []
    score = 0
    max_score = 100
    
    try:
        # 1. Get Result JSON
        copy_from_env("C:/Users/Docker/Desktop/process_capability_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)

        # 2. Get Raw Data for Ground Truth (to verify calculation)
        # We copy it from env to ensure we use the exact file the agent had
        copy_from_env("C:/Users/Docker/Desktop/PowerBITasks/pistonrings.csv", temp_csv.name)
        ground_truth_cpk = calculate_ground_truth_cpk(temp_csv.name, lsl, usl)
        
        # --- Scoring ---

        # Criterion 1: Files Exist (10 pts)
        if result_data.get('pbix_exists') and result_data.get('csv_exists'):
            score += 10
            feedback_parts.append("Files saved")
        else:
            feedback_parts.append("Missing output files")

        # Criterion 2: Files Created During Task (10 pts)
        if result_data.get('pbix_created_during_task') and result_data.get('csv_created_during_task'):
            score += 10
            feedback_parts.append("Files created during task")
        else:
            feedback_parts.append("Files predated task (anti-gaming)")

        # Criterion 3: Visuals Present (30 pts)
        visuals = result_data.get('visual_types', [])
        has_hist = 'clusteredColumnChart' in visuals
        has_card = 'card' in visuals
        has_line = 'lineChart' in visuals
        
        if has_hist: score += 10
        if has_card: score += 10
        if has_line: score += 10
        
        if not (has_hist and has_card and has_line):
            feedback_parts.append(f"Missing some visuals. Found: {visuals}")

        # Criterion 4: Reference Lines (10 pts)
        if result_data.get('has_constant_line'):
            score += 10
            feedback_parts.append("Reference lines detected")
        else:
            feedback_parts.append("Reference lines (LSL/USL) not detected")

        # Criterion 5: Cpk Accuracy (40 pts)
        csv_content = result_data.get('csv_content', '')
        agent_cpk = None
        
        # Parse agent's exported CSV to find the number
        try:
            # Usually export format is headers then data. We look for a float.
            import re
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", csv_content)
            # Filter for numbers that look like Cpk (e.g., 0.5 to 3.0)
            candidates = [float(n) for n in numbers if 0 < float(n) < 5]
            if candidates:
                # The exported card usually contains just the value
                agent_cpk = candidates[0]
        except:
            pass

        if ground_truth_cpk is not None and agent_cpk is not None:
            # Power BI Cpk calculation might vary slightly based on precision
            # Tolerance of 0.05 is reasonable
            error = abs(agent_cpk - ground_truth_cpk)
            if error < 0.05:
                score += 40
                feedback_parts.append(f"Cpk calculation correct (Agent: {agent_cpk:.3f}, Truth: {ground_truth_cpk:.3f})")
            elif error < 0.2:
                score += 20
                feedback_parts.append(f"Cpk calculation close (Agent: {agent_cpk:.3f}, Truth: {ground_truth_cpk:.3f})")
            else:
                feedback_parts.append(f"Cpk incorrect (Agent: {agent_cpk:.3f}, Truth: {ground_truth_cpk:.3f})")
        else:
            feedback_parts.append("Could not verify Cpk value (parsing failed or ground truth error)")

    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }