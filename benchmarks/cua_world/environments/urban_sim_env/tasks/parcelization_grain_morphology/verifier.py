#!/usr/bin/env python3
"""Verifier for parcelization_grain_morphology task."""

import json
import tempfile
import os
import re

def verify_parcelization_morphology(traj, env_info, task_info):
    """
    Verify the urban morphology and parcelization analysis task.
    
    Scoring strategy (100 points max):
    - CSV Generation & Structure:
        - Zone morphology CSV exists and created during task (15 points)
        - Zone morphology CSV has expected columns (10 points)
        - Summary CSV exists and created during task (10 points)
        - Summary CSV has correct aggregation format (10 points)
    - Visualization:
        - Plot image exists, created, and valid size (15 points)
    - Notebook & Logic Check (copied from container):
        - Notebook exists, executed, and handles required datasets (10 points)
        - Deep code check: Implements threshold logic, density calculations, and filtering (30 points)
        
    Passing requires >= 70 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # 1. Read exported task result
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task export result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "Failed to read task result"}

    # 2. Evaluate Zone CSV
    zone_csv_score = 0
    if result.get("zone_csv_exists"):
        zone_csv_score += 5
        if result.get("zone_csv_created"):
            zone_csv_score += 10
            
        cols = result.get("zone_csv_cols", "")
        # Look for expected metrics/IDs in columns
        if 'zone' in cols:
            zone_csv_score += 2
        if 'grain' in cols or 'category' in cols:
            zone_csv_score += 4
        if 'units_per_acre' in cols or 'density' in cols:
            zone_csv_score += 2
        if 'jobs_per_acre' in cols:
            zone_csv_score += 2
            
    score += min(25, zone_csv_score)
    feedback.append(f"Zone CSV points: {min(25, zone_csv_score)}/25")

    # 3. Evaluate Summary CSV
    sum_csv_score = 0
    if result.get("summary_csv_exists"):
        sum_csv_score += 5
        if result.get("summary_csv_created"):
            sum_csv_score += 5
            
        cols = result.get("summary_csv_cols", "")
        # A valid grouped summary should have the category and metric means
        if 'grain' in cols or 'category' in cols:
            sum_csv_score += 4
        if 'unit' in cols or 'job' in cols or 'mean' in cols:
            sum_csv_score += 6
            
    score += min(20, sum_csv_score)
    feedback.append(f"Summary CSV points: {min(20, sum_csv_score)}/20")

    # 4. Evaluate Plot
    plot_score = 0
    if result.get("plot_exists"):
        plot_score += 5
        if result.get("plot_created"):
            plot_score += 5
        if result.get("plot_size_kb", 0) >= 10:  # Valid plots usually > 10kb
            plot_score += 5
            
    score += min(15, plot_score)
    feedback.append(f"Plot points: {min(15, plot_score)}/15")

    # 5. Deep Notebook Code Verification
    nb_score = 0
    
    # Basic Notebook metrics from the export script JSON
    nb_meta = result.get("notebook_analysis", {})
    if result.get("notebook_exists") and result.get("notebook_modified"):
        nb_score += 5
    if nb_meta.get("num_executed_cells", 0) >= 3:
        nb_score += 5
        
    # Copy the notebook to do regex verification on clean code
    temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    try:
        copy_from_env(
            metadata.get('expected_notebook_path', 
                         '/home/ga/urbansim_projects/notebooks/parcelization_morphology.ipynb'), 
            temp_nb.name
        )
        
        with open(temp_nb.name, 'r') as f:
            nb = json.load(f)
            
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        all_code = ''
        for cell in code_cells:
            src = cell.get('source', '')
            if isinstance(src, list):
                src = ''.join(src)
            # Remove comments
            lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
            all_code += '\n'.join(lines) + '\n'
            
        # Strip string literals to prevent agent gaming by printing requirements
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
        
        # Checking for logic implementation
        logic_score = 0
        
        # 1. Did they load the datasets and merge?
        if bool(re.search(r'read_hdf|HDFStore', clean_code)) and bool(re.search(r'parcels|buildings|jobs', clean_code)):
            logic_score += 4
        if bool(re.search(r'merge|join', clean_code)):
            logic_score += 4
            
        # 2. Did they aggregate by zone_id?
        if bool(re.search(r'groupby\s*\(\s*\[?[\'"]?zone_id', all_code)): # strings kept here to match column name
            logic_score += 4
            
        # 3. Did they filter minimum 20 parcels?
        if bool(re.search(r'>=\s*20|>20|20', clean_code)):
            logic_score += 4
            
        # 4. Did they implement the categorization logic? (e.g., pd.cut, apply, loc rules)
        if bool(re.search(r'0\.15', clean_code)) and bool(re.search(r'0\.5', clean_code)) and bool(re.search(r'2\.0', clean_code)):
            logic_score += 6
            
        # 5. Did they calculate density features?
        if bool(re.search(r'/\s*[A-Za-z0-9_]*acres', clean_code, re.IGNORECASE)):
            logic_score += 4
            
        # 6. Grouped summary / Plot?
        if bool(re.search(r'mean\s*\(', clean_code)) and bool(re.search(r'plot|bar', clean_code)):
            logic_score += 4
            
        nb_score += min(30, logic_score)

    except Exception as e:
        feedback.append(f"Deep notebook analysis failed: {e}")
    finally:
        if os.path.exists(temp_nb.name):
            os.unlink(temp_nb.name)
            
    score += min(40, nb_score)
    feedback.append(f"Notebook implementation points: {min(40, nb_score)}/40")

    # Final scoring calculation
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }