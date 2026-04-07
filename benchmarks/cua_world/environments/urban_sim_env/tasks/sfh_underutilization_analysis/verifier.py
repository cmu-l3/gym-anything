#!/usr/bin/env python3
"""Verifier for sfh_underutilization_analysis task."""

import json
import tempfile
import os

def verify_sfh_underutilization(traj, env_info, task_info):
    """Verify single-family housing underutilization analysis was completed.

    Scoring (100 points total):
    - Notebook Execution (20 pts): exists, modified, cells executed
    - CSV Formatting (20 pts): exists, created, right columns
    - Data Logic (30 pts): rows present, valid >= 20 threshold, sorted rates
    - Code Logic (15 pts): read_hdf, merge, groupby, filter logic
    - Plot (15 pts): exists, created, reasonable size
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # Get result JSON via container execution
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # 1. Notebook Execution (20 points)
    nb_score = 0
    if result.get('notebook_exists'):
        nb_score += 5
        if result.get('notebook_modified'):
            nb_score += 5

    nb_a = result.get('notebook_analysis', {})
    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec >= 4:
        nb_score += 10
    elif num_exec > 0:
        nb_score += 5
        
    score += nb_score
    feedback.append(f"Notebook: {nb_score}/20")

    # 2. CSV Formatting (20 points)
    csv_score = 0
    has_cols = False
    if result.get('csv_exists'):
        csv_score += 5
        if result.get('csv_created'):
            csv_score += 5
            
        expected_cols = ["zone_id", "total_large_sfh", "underutilized_sfh", "underutilization_rate"]
        csv_cols = result.get('csv_columns', [])
        
        matches = sum(1 for ec in expected_cols if any(ec in c for c in csv_cols))
        if matches == 4:
            csv_score += 10
            has_cols = True
        elif matches > 0:
            csv_score += matches * 2

    score += csv_score
    feedback.append(f"CSV Formatting: {csv_score}/20")

    # 3. Data Logic (30 points)
    logic_score = 0
    if has_cols and result.get('csv_rows', 0) > 0:
        if result.get('csv_rows', 0) >= 15:
            logic_score += 10
        elif result.get('csv_rows', 0) >= 5:
            logic_score += 5
            
        csv_data = result.get('csv_data', [])
        if len(csv_data) >= 2:
            try:
                rate_idx = -1
                total_idx = -1
                for i, col in enumerate(result.get('csv_columns', [])):
                    if 'rate' in col:
                        rate_idx = i
                    elif 'total' in col:
                        total_idx = i
                
                if rate_idx != -1 and total_idx != -1:
                    valid_totals = True
                    valid_rates = True
                    is_sorted = True
                    
                    prev_rate = 1.0  # Since it should be sorted descending, start at max valid percentage
                    for row in csv_data:
                        if len(row) > max(rate_idx, total_idx):
                            try:
                                total = float(row[total_idx])
                                rate = float(row[rate_idx])
                                
                                if total < 20:
                                    valid_totals = False
                                if not (0.0 <= rate <= 1.0):
                                    valid_rates = False
                                if rate > prev_rate:
                                    is_sorted = False
                                prev_rate = rate
                            except ValueError:
                                pass
                    
                    if valid_totals: logic_score += 5
                    if valid_rates: logic_score += 5
                    if is_sorted: logic_score += 10
            except Exception:
                pass
                
    score += logic_score
    feedback.append(f"Data Logic: {logic_score}/30")

    # 4. Code Logic (15 points)
    code_score = 0
    if nb_a.get('has_read_hdf'): code_score += 3
    if nb_a.get('has_merge'): code_score += 3
    if nb_a.get('has_groupby') and nb_a.get('has_sum'): code_score += 3
    if nb_a.get('has_filter'): code_score += 3
    if nb_a.get('has_persons'): code_score += 3
    
    score += code_score
    feedback.append(f"Code Logic: {code_score}/15")

    # 5. Plot (15 points)
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_created'):
            plot_score += 5
        if result.get('plot_size_kb', 0) >= 10:
            plot_score += 5
    score += plot_score
    feedback.append(f"Plot: {plot_score}/15")

    # Pass condition requires minimum core logic and CSV format
    passed = score >= 70 and has_cols

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }