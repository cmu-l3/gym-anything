#!/usr/bin/env python3
"""Verifier for wind_turbine_performance_analysis task."""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_turbine_performance(traj, env_info, task_info):
    """Verify that the turbine performance analysis was completed correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve and load the exported JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Execution error in export: {result['error']}"}

    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Saved file wind_scada_2022.xlsx not found."}

    # Anti-gaming: Check if file was actively modified
    mtime = result.get("mtime", 0)
    task_start = result.get("task_start", 0)
    if mtime <= task_start:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File was not saved or modified during the task execution."
        }

    score = 0
    feedback_parts = []
    
    # 1. Check SCADA Formulas (Columns E & F)
    scada_formulas = result.get("scada_formulas_sample", [])
    has_e_formula = any("E" in item["col"] and "/6" in item["formula"].replace(" ", "") for item in scada_formulas)
    has_f_formula = any("F" in item["col"] and "IF" in item["formula"].upper() for item in scada_formulas)
    
    if has_e_formula:
        score += 20
        feedback_parts.append("Lost Energy formulas detected (+20)")
    else:
        feedback_parts.append("Missing or incorrect Lost Energy formulas in Col E")
        
    if has_f_formula:
        score += 20
        feedback_parts.append("Operating State IF formulas detected (+20)")
    else:
        feedback_parts.append("Missing or incorrect nested IF formulas in Col F")

    # 2. Check Monthly Report Aggregations
    agent_rep = result.get("agent_report")
    ground_truth = result.get("ground_truth")

    if not agent_rep or not ground_truth:
        feedback_parts.append("Monthly_Report sheet or ground truth missing")
    else:
        # Check COUNTIF aggregations (15 pts)
        a_counts = agent_rep.get("counts", {})
        t_counts = ground_truth.get("counts", {})
        if agent_rep.get("has_countif"):
            matches = sum(1 for k, v in t_counts.items() if a_counts.get(k) == v)
            if matches == 4:
                score += 15
                feedback_parts.append("State counts accurately aggregated (+15)")
            else:
                score += (matches * 3)
                feedback_parts.append(f"State counts partially correct ({matches}/4 matches)")
        else:
            feedback_parts.append("No COUNTIF formulas used")

        # Check SUMIF aggregations (25 pts)
        a_sums = agent_rep.get("sums", {})
        t_sums = ground_truth.get("sums", {})
        if agent_rep.get("has_sumif"):
            matches = sum(1 for k, v in t_sums.items() if abs(a_sums.get(k, -999) - v) < 2.0)
            if matches == 4:
                score += 25
                feedback_parts.append("Lost energy accurately summed (+25)")
            else:
                score += (matches * 6)
                feedback_parts.append(f"Lost energy sums partially correct ({matches}/4 matches)")
        else:
            feedback_parts.append("No SUMIF formulas used")

        # Check Financial Loss (20 pts)
        a_loss = agent_rep.get("financial_loss")
        t_loss = ground_truth.get("financial_loss")
        if a_loss is not None and abs(a_loss - t_loss) < 2.0:
            score += 20
            feedback_parts.append("Financial Loss accurately calculated (+20)")
        else:
            feedback_parts.append(f"Financial loss incorrect or missing (Expected ~{t_loss:.2f})")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }