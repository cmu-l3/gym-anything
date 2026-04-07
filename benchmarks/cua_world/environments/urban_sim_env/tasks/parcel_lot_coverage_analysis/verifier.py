#!/usr/bin/env python3
"""Verifier for parcel_lot_coverage_analysis task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_parcel_lot_coverage(traj, env_info, task_info):
    """
    Verify parcel lot coverage analysis.
    
    Scoring System (100 points):
    - Notebook Execution & Code Logic: 20 pts
    - CSV Structure & Presence: 30 pts
    - JSON Structure & Values: 30 pts
    - Plot Visual Output: 20 pts (Programmatic + VLM)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_cols = metadata.get('expected_csv_columns', [])
    expected_json_keys = metadata.get('expected_json_keys', [])

    score = 0
    feedback = []

    # 1. Read exported result
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # ---------------------------------------------------------
    # Criterion 1: Notebook Execution & Code Logic (20 pts)
    # ---------------------------------------------------------
    nb_score = 0
    temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    try:
        copy_from_env(
            metadata.get('expected_notebook_path', '/home/ga/urbansim_projects/notebooks/lot_coverage_analysis.ipynb'),
            temp_nb.name
        )
        with open(temp_nb.name, 'r') as f:
            nb = json.load(f)

        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        num_exec = sum(1 for c in code_cells if c.get('execution_count') is not None)
        
        if num_exec >= 3:
            nb_score += 5
        elif num_exec > 0:
            nb_score += 2

        all_code = ''
        for c in code_cells:
            src = c.get('source', '')
            all_code += (''.join(src) if isinstance(src, list) else src) + '\n'

        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

        # Keyword checks
        if bool(re.search(r'fillna|replace', clean_code)): nb_score += 3
        if bool(re.search(r'groupby', clean_code)): nb_score += 4
        if bool(re.search(r'sum|mean', clean_code)): nb_score += 4
        if bool(re.search(r'30|29', clean_code)): nb_score += 4

    except Exception as e:
        logger.warning(f"Notebook analysis failed: {e}")
    finally:
        if os.path.exists(temp_nb.name):
            os.unlink(temp_nb.name)

    score += min(20, nb_score)
    feedback.append(f"Notebook: {min(20, nb_score)}/20")

    # ---------------------------------------------------------
    # Criterion 2: CSV Structure & Presence (30 pts)
    # ---------------------------------------------------------
    csv_score = 0
    if result.get('csv_exists'):
        csv_score += 10
        if result.get('csv_created'):
            csv_score += 5
            
        csv_cols = result.get('csv_columns', '')
        cols_matched = sum(1 for c in expected_csv_cols if c in csv_cols)
        if cols_matched >= len(expected_csv_cols):
            csv_score += 10
        elif cols_matched >= 3:
            csv_score += 5
            
        if result.get('csv_rows', 0) > 10:
            csv_score += 5
            
    score += csv_score
    feedback.append(f"CSV: {csv_score}/30")

    # ---------------------------------------------------------
    # Criterion 3: JSON Summary (30 pts)
    # ---------------------------------------------------------
    json_score = 0
    if result.get('json_exists'):
        json_score += 10
        if result.get('json_created'):
            json_score += 5
            
        data = result.get('json_data', {})
        keys_matched = sum(1 for k in expected_json_keys if k in data)
        if keys_matched == len(expected_json_keys):
            json_score += 10
        elif keys_matched >= 2:
            json_score += 5

        # Value validation (Avg coverage must be a sensible ratio 0 to 1)
        avg_cov = data.get('citywide_avg_coverage')
        if isinstance(avg_cov, (int, float)) and 0.0 <= float(avg_cov) <= 1.0:
            json_score += 5
            
    score += json_score
    feedback.append(f"JSON: {json_score}/30")

    # ---------------------------------------------------------
    # Criterion 4: Plot Visual Output & VLM (20 pts)
    # ---------------------------------------------------------
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_created'):
            plot_score += 5
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 5
    
    # Try VLM trajectory verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze this sequence of screenshots from a user analyzing data in Jupyter Lab.
Assess the following:
1. Is Jupyter Lab visible and actively being used to write/execute Python code?
2. Does a chart or plot (e.g., histogram or bar chart) become visible at any point?
Respond in strictly JSON format: {"jupyter_visible": true/false, "plot_visible": true/false}"""
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('jupyter_visible') and parsed.get('plot_visible'):
                    plot_score += 5
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # If VLM fails, grant the points if programmatic plot checks perfectly passed
        if plot_score == 15:
            plot_score += 5

    score += plot_score
    feedback.append(f"Plot: {plot_score}/20")

    # Final tally
    passed = score >= 70 and result.get('csv_exists') and result.get('notebook_modified')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }