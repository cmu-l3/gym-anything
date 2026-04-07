#!/usr/bin/env python3
"""Verifier for day_night_population_estimation task."""

import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_day_night_population(traj, env_info, task_info):
    """
    Verify the day/night population estimation task.

    Scoring (100 pts total):
    - Notebook Exists & Executed (15 pts)
    - Proper Data Merging Logic (20 pts)
    - CSV Output Exists & Correct Rows (10 pts)
    - CSV Format & Columns Correct (15 pts)
    - Math & Sorting Correctness in CSV (25 pts)
    - Choropleth Map Generated (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # =========================================================
    # Part 1: Read standard result JSON
    # =========================================================
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Check Notebook Execution (15 points)
    nb_score = 0
    nb_a = result.get('notebook_analysis', {})
    
    if result.get('notebook_exists') and result.get('notebook_modified'):
        nb_score += 5
    if nb_a.get('num_executed_cells', 0) >= 3:
        nb_score += 5
    if not nb_a.get('has_errors', True):
        nb_score += 5
        
    score += nb_score
    feedback.append(f"Notebook Execution: {nb_score}/15")

    # Code Logic (20 points)
    logic_score = 0
    if nb_a.get('has_read_hdf'): logic_score += 4
    if nb_a.get('has_households') and nb_a.get('has_jobs'): logic_score += 6
    if nb_a.get('has_merge'): logic_score += 5
    if nb_a.get('has_groupby'): logic_score += 5
    score += logic_score
    feedback.append(f"Merging Logic: {logic_score}/20")

    # CSV Exists (10 points)
    csv_exists_score = 0
    if result.get('csv_exists') and result.get('csv_created'):
        csv_exists_score += 5
        if result.get('csv_rows') == metadata.get('top_n_zones', 15):
            csv_exists_score += 5
        elif result.get('csv_rows', 0) > 0:
            csv_exists_score += 2
    score += csv_exists_score
    feedback.append(f"CSV Output Exists: {csv_exists_score}/10")

    # CSV Columns (15 points)
    cols_score = 0
    expected_cols = set(metadata.get('expected_csv_columns', []))
    actual_cols = set(result.get('csv_columns', []))
    
    if expected_cols and expected_cols.issubset(actual_cols):
        cols_score += 15
    elif actual_cols:
        # Partial credit for having some of the required columns
        match_ratio = len(expected_cols.intersection(actual_cols)) / len(expected_cols)
        cols_score += int(15 * match_ratio)
        
    score += cols_score
    feedback.append(f"CSV Columns: {cols_score}/15")

    # Map Generated (15 points)
    map_score = 0
    if result.get('plot_exists') and result.get('plot_created'):
        map_score += 10
        if result.get('plot_size_kb', 0) >= 15:
            map_score += 5
    score += map_score
    feedback.append(f"Map Generated: {map_score}/15")

    # =========================================================
    # Part 2: Rigorous Math & Sorting validation of CSV
    # =========================================================
    math_score = 0
    csv_path = metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/top_daytime_surge_zones.csv')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    
    try:
        copy_from_env(csv_path, temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
            if len(rows) > 0 and expected_cols.issubset(set(reader.fieldnames)):
                math_correct = True
                sorting_correct = True
                prev_surge = float('inf')
                
                for row in rows:
                    try:
                        n_pop = float(row['nighttime_pop'])
                        z_work = float(row['zone_workers'])
                        d_jobs = float(row['daytime_jobs'])
                        d_pop = float(row['daytime_pop'])
                        surge = float(row['surge'])
                        
                        # Validate calculation logic
                        expected_d_pop = (n_pop - z_work) + d_jobs
                        expected_surge = expected_d_pop - n_pop
                        
                        # Allow slight floating point variances
                        if abs(d_pop - expected_d_pop) > 1.0 or abs(surge - expected_surge) > 1.0:
                            math_correct = False
                            
                        # Validate sorting
                        if surge > prev_surge:
                            sorting_correct = False
                        prev_surge = surge
                            
                    except (ValueError, KeyError):
                        math_correct = False
                        sorting_correct = False
                        break
                        
                if math_correct:
                    math_score += 15
                    feedback.append("Math Correctness check passed")
                else:
                    feedback.append("Math logic in CSV output failed validation")
                    
                if sorting_correct:
                    math_score += 10
                    feedback.append("CSV Sorting descending check passed")
                else:
                    feedback.append("CSV is not sorted by surge descending")
            else:
                feedback.append("Could not validate math (CSV missing/incorrect cols)")
    except Exception as e:
        feedback.append(f"Failed to read/validate CSV math: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    score += math_score
    feedback.append(f"Math & Sorting: {math_score}/25")

    # =========================================================
    # Final Evaluation
    # =========================================================
    passed = score >= 70 and math_score >= 15 and result.get('csv_exists', False) and result.get('plot_exists', False)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }