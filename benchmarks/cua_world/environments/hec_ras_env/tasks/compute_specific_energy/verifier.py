#!/usr/bin/env python3
"""
Verifier for compute_specific_energy task.

Uses ground truth calculated inside the container (which has the HEC-RAS libraries)
to verify the agent's output.
"""

import json
import os
import tempfile
import logging
import csv
import re
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_specific_energy(traj, env_info, task_info):
    """
    Verify the specific energy computation task.
    
    Criteria:
    1. Output files exist and were created during task.
    2. Report contains correct identified Peak Q and River Station.
    3. Calculated Critical Depth matches ground truth (within tolerance).
    4. Flow Regime classification is correct.
    5. CSV data follows the specific energy curve physics.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve all files
    files_to_copy = {
        "result": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth.json",
        "agent_csv": "/tmp/agent_curve.csv",
        "agent_report": "/tmp/agent_report.txt"
    }
    
    local_files = {}
    
    # Use a temp directory
    with tempfile.TemporaryDirectory() as tmpdir:
        for name, path in files_to_copy.items():
            local_path = os.path.join(tmpdir, name)
            try:
                copy_from_env(path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {name}: {e}")

        # Basic Check: Result JSON
        if "result" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result metadata"}
        
        with open(local_files["result"], 'r') as f:
            task_result = json.load(f)
            
        # Basic Check: Ground Truth (Critical for verification)
        if "ground_truth" not in local_files:
            return {"passed": False, "score": 0, "feedback": "System error: Ground truth generation failed inside container"}
            
        with open(local_files["ground_truth"], 'r') as f:
            gt = json.load(f)
            if "error" in gt:
                 return {"passed": False, "score": 0, "feedback": f"System error in ground truth: {gt['error']}"}

        score = 0
        feedback_parts = []
        
        # --- Criterion 1: Files Exist (20 pts) ---
        if task_result.get("csv_exists") and task_result.get("report_exists"):
            score += 20
            feedback_parts.append("Output files exist")
        elif task_result.get("csv_exists") or task_result.get("report_exists"):
            score += 10
            feedback_parts.append("Partial output files found")
        else:
            feedback_parts.append("No output files found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        # --- Criterion 2: Correct Identification (Peak Q, Station) (20 pts) ---
        report_data = {}
        if "agent_report" in local_files:
            try:
                with open(local_files["agent_report"], 'r') as f:
                    content = f.read()
                    # Parse lines like "Key: Value"
                    for line in content.splitlines():
                        if ":" in line:
                            key, val = line.split(":", 1)
                            report_data[key.strip()] = val.strip()
            except Exception:
                feedback_parts.append("Could not parse report file")

        # Check River Station
        agent_rs = report_data.get("Cross Section River Station", "")
        gt_rs = gt.get("river_station", "")
        if agent_rs == gt_rs:
            score += 10
            feedback_parts.append(f"Correct Cross Section ({gt_rs})")
        else:
            feedback_parts.append(f"Wrong Cross Section (Expected {gt_rs}, Got {agent_rs})")
            
        # Check Peak Discharge
        try:
            agent_q = float(report_data.get("Peak Discharge (cfs)", 0))
            gt_q = float(gt.get("peak_discharge", 0))
            if math.isclose(agent_q, gt_q, rel_tol=0.05):
                score += 10
                feedback_parts.append(f"Peak Discharge accurate ({agent_q} cfs)")
            else:
                feedback_parts.append(f"Peak Discharge inaccurate (Expected ~{gt_q:.1f}, Got {agent_q})")
        except ValueError:
            feedback_parts.append("Invalid Peak Discharge value")

        # --- Criterion 3: Critical Depth & Physics (30 pts) ---
        try:
            agent_yc = float(report_data.get("Critical Depth (ft)", 0))
            gt_yc = float(gt.get("critical_depth", 0))
            
            if math.isclose(agent_yc, gt_yc, rel_tol=0.1):
                score += 15
                feedback_parts.append(f"Critical Depth accurate ({agent_yc} ft)")
            else:
                feedback_parts.append(f"Critical Depth inaccurate (Expected ~{gt_yc:.2f}, Got {agent_yc})")
        except ValueError:
            pass

        # Check Flow Regime
        agent_regime = report_data.get("Flow Regime", "").lower()
        gt_regime = gt.get("flow_regime", "").lower()
        if agent_regime and gt_regime in agent_regime:
            score += 15
            feedback_parts.append("Flow Regime correct")
        else:
            feedback_parts.append(f"Flow Regime incorrect (Expected {gt_regime})")

        # --- Criterion 4: CSV Curve Accuracy (30 pts) ---
        if "agent_csv" in local_files:
            try:
                with open(local_files["agent_csv"], 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                if len(rows) > 100:
                    # Check a sample point (e.g., at depth near Critical Depth)
                    # We'll just check if minimum energy in CSV is close to GT minimum energy
                    min_e_csv = float('inf')
                    for row in rows:
                        try:
                            e = float(row.get('specific_energy_ft', row.get('specific_energy', float('inf'))))
                            if e < min_e_csv:
                                min_e_csv = e
                        except ValueError:
                            continue
                            
                    gt_min_e = float(gt.get("min_specific_energy", 0))
                    
                    if math.isclose(min_e_csv, gt_min_e, rel_tol=0.15):
                        score += 30
                        feedback_parts.append("Specific Energy Curve data valid")
                    else:
                        score += 10 # Partial credit for having data
                        feedback_parts.append(f"Specific Energy Curve data deviates (Min E: {min_e_csv:.2f} vs {gt_min_e:.2f})")
                else:
                    feedback_parts.append("CSV has too few rows")
            except Exception as e:
                feedback_parts.append(f"Error analyzing CSV: {str(e)}")
        else:
            feedback_parts.append("CSV file missing")

        # Check Anti-Gaming (Timestamps)
        if not (task_result.get("csv_created_during_task") and task_result.get("report_created_during_task")):
            score = min(score, 40) # Cap score if files look old
            feedback_parts.append("WARNING: Output files timestamps indicate pre-existence or copy")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }