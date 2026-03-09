#!/usr/bin/env python3
"""
Verifier for developer_skills_analysis task.

Scoring (100 points total):
1. PBIX Saved (10 pts): File exists on Desktop.
2. Created During Task (10 pts): Timestamp check (Anti-gaming).
3. Visuals Present (20 pts): Bar Chart and Table detected.
4. Measures Created (20 pts): 'Respondent_Count' and 'Avg_Salary' found in model.
5. CSV Exported (20 pts): 'language_stats.csv' exists.
6. Transformation Verify (20 pts): CSV contains no semicolons (proves split-to-rows).

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_developer_skills_analysis(traj, env_info, task_info):
    """
    Verify the developer skills analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/skills_analysis_result.json", temp_file.name)
    except Exception as e:
        logger.warning(f"Failed to copy result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Result file not found (Task script likely failed)"}

    try:
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Criterion 1: PBIX Saved (10 pts)
    if result.get('file_exists'):
        score += 10
        feedback.append("Skills_Analysis.pbix saved.")
    else:
        feedback.append("Skills_Analysis.pbix NOT found.")

    # Criterion 2: Created During Task (10 pts)
    if result.get('file_created_during_task'):
        score += 10
    elif result.get('file_exists'):
        feedback.append("File timestamp indicates it wasn't created during this session.")

    # Criterion 3: Visuals Present (20 pts)
    visuals = result.get('visual_types', [])
    has_bar = any('bar' in v.lower() for v in visuals)
    has_table = any('table' in v.lower() for v in visuals)
    
    if has_bar and has_table:
        score += 20
        feedback.append("Correct visuals (Bar Chart + Table) found.")
    elif has_bar or has_table:
        score += 10
        feedback.append(f"Partial visuals found: {visuals}")
    else:
        feedback.append("No required visuals found.")

    # Criterion 4: Measures Created (20 pts)
    measures = result.get('measures_found', [])
    req_measures = ['Respondent_Count', 'Avg_Salary']
    found_measures = [m for m in req_measures if m in measures]
    
    if len(found_measures) == 2:
        score += 20
        feedback.append("DAX Measures (Respondent_Count, Avg_Salary) found.")
    elif len(found_measures) == 1:
        score += 10
        feedback.append(f"Missing measure. Found: {found_measures}")
    else:
        feedback.append("No DAX measures found.")

    # Criterion 5: CSV Exported (20 pts)
    if result.get('csv_exists'):
        score += 20
        feedback.append("language_stats.csv exported.")
    else:
        feedback.append("language_stats.csv NOT found.")

    # Criterion 6: Transformation Verified (20 pts)
    # This is critical - did they actually split the column?
    if result.get('csv_exists'):
        if result.get('csv_clean_split'):
            score += 20
            feedback.append("Data transformation verified (No semicolons in output).")
        else:
            feedback.append("Data transformation FAILED: Semicolons found in output CSV (did not split to rows).")
            # If they failed the core transformation, penalize visuals too as they are likely wrong
            # But the scoring above handles separate components independently

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }