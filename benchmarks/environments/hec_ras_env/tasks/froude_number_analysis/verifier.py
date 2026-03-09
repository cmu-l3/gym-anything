#!/usr/bin/env python3
"""
Verifier for Froude Number Analysis Task.

This verifier compares the agent's generated CSV and Report against 
Ground Truth data generated directly from the HDF5 file inside the container.
"""

import json
import os
import csv
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_froude_analysis(traj, env_info, task_info):
    """
    Verify the Froude analysis task.
    
    Criteria:
    1. CSV file exists and has correct columns (10 pts)
    2. Correct number of cross-sections in CSV (10 pts)
    3. Peak timestep correctly identified (10 pts)
    4. Froude numbers match ground truth within 5% (25 pts)
    5. Flow regime classifications are correct based on Froude numbers (10 pts)
    6. Internal consistency of agent's data (Fr = V/sqrt(gD)) (10 pts)
    7. Report file exists with required lines (10 pts)
    8. Report statistics match ground truth (10 pts)
    9. Files created during task (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    result = {}
    with tempfile.NamedTemporaryFile(delete=True, suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # Load Ground Truth
    ground_truth = {}
    with tempfile.NamedTemporaryFile(delete=True, suffix='.json') as tf:
        try:
            copy_from_env("/tmp/ground_truth.json", tf.name)
            tf.seek(0)
            ground_truth = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}

    if "error" in ground_truth:
        return {"passed": False, "score": 0, "feedback": f"Ground truth generation error: {ground_truth['error']}"}

    # Load Agent CSV
    agent_rows = []
    if result.get("csv_exists"):
        with tempfile.NamedTemporaryFile(delete=True, suffix='.csv') as tf:
            try:
                copy_from_env("/tmp/agent_froude.csv", tf.name)
                tf.seek(0)
                # Read CSV
                try:
                    reader = csv.DictReader(open(tf.name, 'r'))
                    agent_rows = list(reader)
                except Exception as e:
                    logger.warning(f"Failed to parse CSV: {e}")
            except Exception as e:
                logger.warning(f"Failed to copy CSV: {e}")

    # Load Agent Report
    agent_report_lines = []
    if result.get("report_exists"):
        with tempfile.NamedTemporaryFile(delete=True, suffix='.txt') as tf:
            try:
                copy_from_env("/tmp/agent_report.txt", tf.name)
                tf.seek(0)
                agent_report_lines = open(tf.name, 'r').read().splitlines()
            except Exception as e:
                logger.warning(f"Failed to copy Report: {e}")

    score = 0
    feedback = []

    # --- Criterion 1: CSV Structure (10 pts) ---
    required_cols = {'CrossSection', 'Velocity_fps', 'HydraulicDepth_ft', 'FroudeNumber', 'FlowRegime'}
    if agent_rows:
        headers = set(agent_rows[0].keys())
        if required_cols.issubset(headers):
            score += 10
            feedback.append("CSV structure correct.")
        else:
            feedback.append(f"CSV missing columns. Found: {headers}, Expected: {required_cols}")
    else:
        feedback.append("CSV file empty or unreadable.")

    # --- Criterion 2: Cross-section count (10 pts) ---
    gt_count = ground_truth.get('total_cross_sections', 0)
    agent_count = len(agent_rows)
    if agent_count == gt_count and gt_count > 0:
        score += 10
        feedback.append(f"Correct row count ({agent_count}).")
    elif gt_count > 0:
        feedback.append(f"Incorrect row count: {agent_count} (Expected: {gt_count}).")

    # --- Criterion 3: Peak Timestep (10 pts) ---
    # We check this via the report usually, but let's check values first
    # If the values match, they found the right timestep.
    # Alternatively, check report for "Peak Flow Timestep Index: <idx>"
    gt_idx = ground_truth.get('peak_timestep_index', -1)
    timestep_found = False
    for line in agent_report_lines:
        if "Peak Flow Timestep Index:" in line:
            try:
                val = int(line.split(":")[1].strip())
                if val == gt_idx:
                    score += 10
                    timestep_found = True
                    feedback.append(f"Correct peak timestep identified ({val}).")
                else:
                    feedback.append(f"Wrong peak timestep: {val} (Expected: {gt_idx}).")
            except:
                pass
            break
    if not timestep_found:
        feedback.append("Peak timestep not found in report.")

    # --- Criterion 4: Froude Values (25 pts) ---
    # Compare sequence of Froude numbers
    # We assume row order matches. If not, we might need to map by name.
    # Let's try matching by index first.
    correct_fr = 0
    total_comparisons = min(len(agent_rows), len(ground_truth['cross_sections']))
    
    for i in range(total_comparisons):
        try:
            agent_fr = float(agent_rows[i]['FroudeNumber'])
            gt_fr = ground_truth['cross_sections'][i]['froude']
            
            # 5% tolerance
            if math.isclose(agent_fr, gt_fr, rel_tol=0.05, abs_tol=0.01):
                correct_fr += 1
        except:
            pass
            
    if total_comparisons > 0:
        fr_accuracy = correct_fr / total_comparisons
        if fr_accuracy >= 0.9:
            score += 25
            feedback.append("Froude numbers accurate (>90% match).")
        elif fr_accuracy >= 0.5:
            score += 15
            feedback.append(f"Froude numbers partially accurate ({fr_accuracy:.1%} match).")
        else:
            feedback.append(f"Froude numbers inaccurate ({fr_accuracy:.1%} match).")
    else:
        feedback.append("No Froude numbers to compare.")

    # --- Criterion 5: Classification (10 pts) ---
    correct_class = 0
    for row in agent_rows:
        try:
            fr = float(row['FroudeNumber'])
            regime = row['FlowRegime'].strip().lower()
            expected = "critical"
            if fr < 0.99: expected = "subcritical" # tolerance for float
            elif fr > 1.01: expected = "supercritical"
            
            if expected in regime:
                correct_class += 1
        except:
            pass
            
    if len(agent_rows) > 0 and (correct_class / len(agent_rows)) > 0.9:
        score += 10
        feedback.append("Flow regimes classified correctly.")

    # --- Criterion 6: Internal Consistency (10 pts) ---
    # Fr = V / sqrt(g * D)
    consistent = 0
    g = 32.174
    for row in agent_rows:
        try:
            v = float(row['Velocity_fps'])
            d = float(row['HydraulicDepth_ft'])
            fr_rep = float(row['FroudeNumber'])
            
            if d > 0:
                fr_calc = v / math.sqrt(g * d)
                if math.isclose(fr_calc, fr_rep, rel_tol=0.05):
                    consistent += 1
            elif fr_rep == 0:
                consistent += 1
        except:
            pass

    if len(agent_rows) > 0 and (consistent / len(agent_rows)) > 0.9:
        score += 10
        feedback.append("Data internally consistent.")

    # --- Criterion 7: Report Existence (10 pts) ---
    required_lines = [
        "Total Cross Sections:", 
        "Peak Flow Timestep Index:", 
        "Subcritical Sections:", 
        "Supercritical Sections:",
        "Mean Froude Number:"
    ]
    present = 0
    for req in required_lines:
        if any(req in line for line in agent_report_lines):
            present += 1
            
    if present == len(required_lines):
        score += 10
        feedback.append("Report format correct.")
    elif present > 0:
        score += 5
        feedback.append("Report format incomplete.")

    # --- Criterion 8: Report Statistics (10 pts) ---
    # Check one stat: Mean Froude
    stat_ok = False
    for line in agent_report_lines:
        if "Mean Froude Number:" in line:
            try:
                val = float(line.split(":")[1].strip())
                if math.isclose(val, ground_truth['mean_froude'], rel_tol=0.05):
                    stat_ok = True
            except:
                pass
    if stat_ok:
        score += 10
        feedback.append("Report statistics match ground truth.")

    # --- Criterion 9: Anti-gaming (5 pts) ---
    if result.get("csv_created_during_task") and result.get("report_created_during_task"):
        score += 5
    else:
        feedback.append("Files not created during task window.")

    return {
        "passed": score >= 60 and len(agent_rows) > 0,
        "score": score,
        "feedback": " | ".join(feedback)
    }