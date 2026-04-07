#!/usr/bin/env python3
"""Verifier for micro_enterprise_fabric_analysis task."""

import json
import tempfile
import os
import re
import csv

def verify_micro_enterprise_fabric(traj, env_info, task_info):
    """Verify micro enterprise analysis was run successfully.

    Scoring (100 points total):
    - Notebook Execution (15 pts): Created, executed, no errors
    - Code Methodology (15 pts): Data loading, merges, grouping, charting
    - CSV Structure (20 pts): Exists, 15 rows, correct 9 columns
    - CSV Math Consistency (20 pts): Row logic is mathematically sound
    - CSV Constraints (15 pts): Threshold filter applied, correct sort
    - Chart Generation (15 pts): PNG exists, reasonable size

    Pass threshold: 70 points AND must pass CSV math/constraints.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/top_micro_enterprise_zones.csv')
    expected_plot_path = metadata.get('expected_plot_path', '/home/ga/urbansim_projects/output/business_size_composition.png')
    
    score = 0
    feedback = []

    # ==========================================
    # 1. Read task_result.json
    # ==========================================
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not result:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # ==========================================
    # 2. Notebook Execution & Methodology (30 pts)
    # ==========================================
    nb_a = result.get('notebook_analysis', {})
    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5
    
    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec >= 4:
        score += 10
    elif num_exec > 0:
        score += 5

    meth_score = 0
    if nb_a.get('has_hdf') or nb_a.get('has_pandas'): meth_score += 3
    if nb_a.get('has_merge'): meth_score += 3
    if nb_a.get('has_groupby'): meth_score += 3
    if nb_a.get('has_binning'): meth_score += 3
    if nb_a.get('has_to_csv') and nb_a.get('has_savefig'): meth_score += 3
    score += meth_score
    feedback.append(f"Notebook & Methodology: {15 + meth_score}/30")

    # ==========================================
    # 3. Chart Generation (15 pts)
    # ==========================================
    chart_score = 0
    if result.get('plot_exists'):
        chart_score += 5
        if result.get('plot_created'):
            chart_score += 5
        if result.get('plot_size_kb', 0) >= 15:
            chart_score += 5
        elif result.get('plot_size_kb', 0) >= 5:
            chart_score += 2
    score += chart_score
    feedback.append(f"Chart Output: {chart_score}/15")

    # ==========================================
    # 4. CSV Structure, Math Consistency, Constraints (55 pts)
    # ==========================================
    csv_structure_score = 0
    csv_math_score = 0
    csv_constraint_score = 0
    
    math_passed = False
    constraint_passed = False

    if result.get('csv_exists'):
        csv_structure_score += 5
        
        # Download and inspect CSV
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(expected_csv_path, temp_csv.name)
            
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                fieldnames = [c.lower().strip() for c in (reader.fieldnames or [])]
            
            # Row count check
            if len(rows) == 15:
                csv_structure_score += 5
            elif len(rows) > 0:
                csv_structure_score += 2
                
            # Column check
            required_cols = [
                'zone_id', 'total_business_bldgs', 'micro_small_bldgs', 
                'medium_bldgs', 'large_bldgs', 'micro_small_bldg_pct', 
                'total_jobs', 'micro_small_jobs', 'micro_small_job_pct'
            ]
            
            matched_cols = 0
            for req in required_cols:
                if any(req in f for f in fieldnames):
                    matched_cols += 1
                    
            if matched_cols == len(required_cols):
                csv_structure_score += 10
            else:
                csv_structure_score += int((matched_cols / len(required_cols)) * 10)

            # --- MATH AND CONSTRAINT CHECKS ---
            if len(rows) > 0 and matched_cols >= 5: # Need enough columns to check math
                math_errors = 0
                constraint_errors = 0
                prev_pct = 999.0
                
                # Try to map columns if not exactly named but contain keywords
                col_map = {}
                for req in required_cols:
                    for f in fieldnames:
                        if req in f:
                            col_map[req] = f
                            break
                            
                for row in rows:
                    try:
                        t_bldgs = float(row.get(col_map.get('total_business_bldgs', ''), 0))
                        micro_b = float(row.get(col_map.get('micro_small_bldgs', ''), 0))
                        med_b = float(row.get(col_map.get('medium_bldgs', ''), 0))
                        large_b = float(row.get(col_map.get('large_bldgs', ''), 0))
                        micro_pct = float(row.get(col_map.get('micro_small_bldg_pct', ''), 0))
                        
                        t_jobs = float(row.get(col_map.get('total_jobs', ''), 0))
                        micro_jobs = float(row.get(col_map.get('micro_small_jobs', ''), 0))
                        micro_j_pct = float(row.get(col_map.get('micro_small_job_pct', ''), 0))
                        
                        # Math 1: Sum of building parts
                        if abs((micro_b + med_b + large_b) - t_bldgs) > 0.5:
                            math_errors += 1
                            
                        # Math 2: Building Pct check
                        if t_bldgs > 0:
                            calc_pct = (micro_b / t_bldgs) * 100
                            if calc_pct > 1.0 and micro_pct <= 1.0: # Account for 0-1 scale output
                                calc_pct /= 100.0
                            if abs(calc_pct - micro_pct) > 1.0:
                                math_errors += 1
                                
                        # Constraint 1: Threshold
                        if t_bldgs < 20:
                            constraint_errors += 1
                            
                        # Constraint 2: Sorting (descending)
                        if micro_pct > prev_pct + 0.1: # Allow tiny float tolerance
                            constraint_errors += 1
                        prev_pct = micro_pct
                        
                    except (ValueError, TypeError):
                        math_errors += 1
                
                # Math Scoring
                if math_errors == 0:
                    csv_math_score = 20
                    math_passed = True
                elif math_errors <= 3:
                    csv_math_score = 10
                    
                # Constraint Scoring
                if constraint_errors == 0 and len(rows) == 15:
                    csv_constraint_score = 15
                    constraint_passed = True
                elif constraint_errors <= 2:
                    csv_constraint_score = 7

        except Exception as e:
            feedback.append(f"Error reading CSV for evaluation: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    score += csv_structure_score
    score += csv_math_score
    score += csv_constraint_score
    feedback.append(f"CSV Check: Structure {csv_structure_score}/20, Math {csv_math_score}/20, Constraints {csv_constraint_score}/15")

    # ==========================================
    # 5. Final Determination
    # ==========================================
    # Must meet key structural integrity of the analysis to pass (avoids hallucinated tables)
    key_criteria_met = math_passed and constraint_passed
    passed = score >= 70 and key_criteria_met

    if score >= 70 and not key_criteria_met:
        feedback.append("Failed: Score was high enough, but critical mathematical consistency or data constraints were violated (potential hallucination).")

    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback)
    }