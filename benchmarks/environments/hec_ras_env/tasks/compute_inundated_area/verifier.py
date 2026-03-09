#!/usr/bin/env python3
"""
Verifier for compute_inundated_area task.
Checks:
1. Accuracy of reported acreage against ground truth (calculated from HDF5).
2. Existence and validity of support files (CSV, Plot).
3. Evidence of programmatic solution (script existence).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_inundated_area(traj, env_info, task_info):
    """
    Verify the Inundated Area calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Report & Accuracy (40 pts)
    report = result.get('agent_report', {})
    ground_truth = result.get('ground_truth_acres', 0.0)
    
    if not report.get('exists'):
        feedback_parts.append("Report file not found")
    else:
        try:
            agent_val = float(report.get('value', 0.0))
            if ground_truth > 0:
                diff = abs(agent_val - ground_truth)
                percent_error = (diff / ground_truth) * 100
                
                if percent_error <= 5.0:
                    score += 40
                    feedback_parts.append(f"Accuracy valid ({agent_val} vs {ground_truth:.2f} acres, {percent_error:.1f}% error)")
                elif percent_error <= 10.0:
                    score += 20
                    feedback_parts.append(f"Accuracy acceptable ({agent_val} vs {ground_truth:.2f} acres, {percent_error:.1f}% error)")
                else:
                    feedback_parts.append(f"Accuracy failed ({agent_val} vs {ground_truth:.2f} acres, {percent_error:.1f}% error)")
            else:
                # If GT failed, we can't score accuracy strictly, but give partial if value looks reasonable (e.g., >0)
                if agent_val > 0:
                    score += 20
                    feedback_parts.append("Ground truth unavailable, but agent reported positive value")
                else:
                    feedback_parts.append("Invalid reported value (0 or null)")
        except ValueError:
            feedback_parts.append("Could not parse numeric value from report")

    # 2. Check CSV (20 pts)
    csv = result.get('agent_csv', {})
    if csv.get('exists'):
        if csv.get('lines', 0) > 5: # Minimal check for content
            score += 20
            feedback_parts.append("CSV file exists with data")
        else:
            score += 10
            feedback_parts.append("CSV file exists but appears empty/short")
    else:
        feedback_parts.append("CSV file missing")

    # 3. Check Visualization (20 pts)
    plot = result.get('agent_plot', {})
    if plot.get('exists'):
        score += 20
        feedback_parts.append("Plot file generated")
    else:
        feedback_parts.append("Plot file missing")

    # 4. Check Methodology (Script) (20 pts)
    script = result.get('agent_script', {})
    if script.get('exists'):
        score += 20
        feedback_parts.append("Analysis script detected")
    else:
        feedback_parts.append("No analysis script found")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }