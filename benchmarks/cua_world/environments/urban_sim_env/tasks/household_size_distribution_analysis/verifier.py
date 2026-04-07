#!/usr/bin/env python3
"""Verifier for household_size_distribution_analysis task."""

import json
import tempfile
import os
import re

def verify_household_size_distribution(traj, env_info, task_info):
    """Verify household size distribution analysis was completed.

    Scoring (100 points total):
    - Notebook Code & Execution (30 pts)
    - Output Files Exist & Modified (20 pts)
    - CSV Validation (30 pts)
    - Visualization Quality (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # Copy task result JSON
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

    # Criterion 1: Notebook existence and basic execution (30 pts)
    if result.get('notebook_exists'):
        score += 5
        if result.get('notebook_modified'):
            score += 5

        nb_a = result.get('notebook_analysis', {})
        num_exec = nb_a.get('num_executed_cells', 0)
        if num_exec >= 3:
            score += 10
        elif num_exec > 0:
            score += 5
            
        if nb_a.get('has_merge'):
            score += 3
        if nb_a.get('has_groupby'):
            score += 3
        if nb_a.get('has_filter'):
            score += 4
        
        feedback.append(f"Notebook execution and code check passed (executed cells: {num_exec})")
    else:
        feedback.append("Notebook not found")

    # Criterion 2: Output Files (20 pts)
    csv_exists = result.get('csv_exists', False)
    plot_exists = result.get('plot_exists', False)
    
    if csv_exists:
        score += 5
        if result.get('csv_created'):
            score += 5
    else:
        feedback.append("CSV output not found")
        
    if plot_exists:
        score += 5
        if result.get('plot_created'):
            score += 5
    else:
        feedback.append("Plot output not found")

    # Criterion 3: CSV Validation (30 pts)
    if csv_exists:
        cols = result.get('csv_columns', '')
        req_cols = metadata.get('expected_csv_columns', [])
        
        cols_present = sum(1 for col in req_cols if col in cols)
        score += int((cols_present / max(1, len(req_cols))) * 15)
        
        if cols_present == len(req_cols):
            feedback.append("All required CSV columns present")
        else:
            feedback.append(f"Missing some CSV columns (found {cols_present}/{len(req_cols)})")

        data_preview = result.get('csv_data_preview', [])
        valid_rows = 0
        math_valid = 0
        
        if data_preview:
            score += 5 # At least some data
            for row in data_preview:
                row_keys_lower = {k.lower().strip() if k else '': k for k in row.keys()}
                
                # Check for >= 50 threshold
                th_key = next((k for l, k in row_keys_lower.items() if 'total' in l and 'household' in l), None)
                if th_key and row.get(th_key):
                    try:
                        if float(row[th_key]) >= metadata.get('min_households_filter', 50):
                            valid_rows += 1
                    except ValueError:
                        pass
                
                # Math check: counts sum to total
                c1_key = next((k for l, k in row_keys_lower.items() if '1_person' in l or '1person' in l), None)
                c2_key = next((k for l, k in row_keys_lower.items() if '2_person' in l or '2person' in l), None)
                c3_key = next((k for l, k in row_keys_lower.items() if '3plus' in l or '3_plus' in l or '3+' in l), None)
                
                if th_key and c1_key and c2_key and c3_key and row.get(th_key) and row.get(c1_key) and row.get(c2_key) and row.get(c3_key):
                    try:
                        th = float(row[th_key])
                        c1 = float(row[c1_key])
                        c2 = float(row[c2_key])
                        c3 = float(row[c3_key])
                        # Allow small rounding errors just in case
                        if abs(th - (c1 + c2 + c3)) < 2:
                            math_valid += 1
                    except ValueError:
                        pass
            
            if valid_rows > 0:
                score += 5 # Filter works
                feedback.append(f"Data filter check passed (>= 50 households)")
            if math_valid > 0:
                score += 5 # Math works
                feedback.append(f"Mathematical validation passed")

    # Criterion 4: Visualization Quality (20 pts)
    if plot_exists:
        size_kb = result.get('plot_size_kb', 0)
        if size_kb > 20:
            score += 20
            feedback.append("Plot size looks good for a chart")
        elif size_kb > 5:
            score += 10
            feedback.append("Plot file exists but size is small")
        else:
            feedback.append("Plot file is too small to be a valid chart")

    # Additional Code Analysis to prevent gaming
    temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    try:
        copy_from_env("/home/ga/urbansim_projects/notebooks/household_size_analysis.ipynb", temp_nb.name)
        with open(temp_nb.name, 'r') as f:
            nb = json.load(f)

        all_code = ''
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        for cell in code_cells:
            src = cell.get('source', '')
            if isinstance(src, list):
                src = ''.join(src)
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'

        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

        has_households = bool(re.search(r'households', clean_code))
        has_buildings = bool(re.search(r'buildings', clean_code))
        has_parcels = bool(re.search(r'parcels', clean_code))
        has_merge = bool(re.search(r'merge|join', clean_code))
        
        if not (has_households and has_buildings and has_parcels and has_merge):
            score = max(0, score - 20)
            feedback.append("PENALTY: Code lacks required data merging operations")

    except Exception:
        pass
    finally:
        if os.path.exists(temp_nb.name):
            os.unlink(temp_nb.name)

    passed = score >= 70 and csv_exists and plot_exists
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback)
    }