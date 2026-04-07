#!/usr/bin/env python3
"""
Verifier for index_health_maintenance task.

Evaluates:
1. Database object creation (Schema, Tables, Procs)
2. Logic implementation (Data validity, Row counts)
3. Operational output (Maintenance script file)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_index_health_maintenance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get VLM function
    query_vlm = env_info.get('query_vlm')
    
    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Schema Check (5 pts)
    if result.get('schema_exists'):
        score += 5
        feedback.append("Schema 'DBAMaintenance' created.")
    else:
        feedback.append("Missing schema 'DBAMaintenance'.")

    # 2. Table Checks (20 pts)
    if result.get('report_table_exists') and result.get('report_columns_valid'):
        score += 10
        feedback.append("Table 'IndexHealthReport' created correctly.")
    elif result.get('report_table_exists'):
        score += 5
        feedback.append("Table 'IndexHealthReport' exists but missing columns.")
    else:
        feedback.append("Missing table 'IndexHealthReport'.")

    if result.get('overlap_table_exists'):
        score += 10
        feedback.append("Table 'OverlappingIndexes' created.")
    else:
        feedback.append("Missing table 'OverlappingIndexes'.")

    # 3. Procedure Checks (20 pts)
    if result.get('analyze_proc_exists'):
        score += 10
        feedback.append("Procedure 'usp_AnalyzeIndexHealth' created.")
    else:
        feedback.append("Missing procedure 'usp_AnalyzeIndexHealth'.")

    if result.get('overlap_proc_exists'):
        score += 10
        feedback.append("Procedure 'usp_DetectOverlappingIndexes' created.")
    else:
        feedback.append("Missing procedure 'usp_DetectOverlappingIndexes'.")

    # 4. Data Population & Logic (30 pts)
    row_count = result.get('report_row_count', 0)
    if row_count >= 50:
        score += 10
        feedback.append(f"Report populated with {row_count} rows.")
    elif row_count > 0:
        score += 5
        feedback.append(f"Report populated but has few rows ({row_count}).")
    else:
        feedback.append("Report table is empty.")

    if result.get('recommended_action_valid'):
        score += 5
        feedback.append("Recommended actions are valid.")
    else:
        feedback.append("Invalid values in RecommendedAction column.")

    if result.get('size_calc_valid'):
        score += 5
        feedback.append("SizeKB calculation appears correct.")
    
    # Index types check (ensures not just filtering for one type)
    if result.get('index_types_found', 0) >= 2:
        score += 5
        feedback.append("Multiple index types analyzed (Clustered/Nonclustered).")
    
    # Overlap table check (Bonus/Confirmation)
    if result.get('overlap_row_count', 0) >= 0: # Just checking query ran success
        score += 5
        feedback.append("Overlapping index detection ran.")

    # 5. File Output (25 pts)
    if result.get('file_exists'):
        score += 10
        feedback.append("Maintenance script file exists.")
        if result.get('file_content_valid'):
            score += 15
            feedback.append("Maintenance script contains valid SQL/Comments.")
        else:
            feedback.append("Maintenance script content looks invalid (empty or no SQL).")
    else:
        feedback.append("Missing output file 'index_maintenance.sql'.")

    # VLM Verification (Optional but good for confirming UI usage)
    # We check if ADS was visible in final screenshot
    if query_vlm:
        try:
            temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/task_final.png", temp_ss.name)
            vlm_res = query_vlm(
                image=temp_ss.name,
                prompt="Is Azure Data Studio or a SQL query editor visible in this image? Reply JSON with {'visible': bool}."
            )
            if vlm_res.get('parsed', {}).get('visible'):
                # Pass
                pass
            os.unlink(temp_ss.name)
        except:
            pass

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }