#!/usr/bin/env python3
"""Verifier for service worker spatial mismatch task."""

import json
import tempfile
import os
import re

def verify_spatial_mismatch(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

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

    # Notebook criteria (20 pts)
    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5
        nb_a = result.get('notebook_analysis', {})
        if nb_a.get('has_code'):
            score += 5
        
        num_exec = nb_a.get('num_executed_cells', 0)
        if num_exec >= 4:
            score += 10
        elif num_exec > 0:
            score += 5
        feedback.append(f"Notebook check: {min(20, score)}/20")

    # Code Methodology criteria (30 pts)
    method_score = 0
    if result.get('notebook_exists'):
        temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
        try:
            copy_from_env(
                metadata.get('expected_notebook_path', '/home/ga/urbansim_projects/notebooks/spatial_mismatch.ipynb'),
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
                lines = [l for l in src.split('\n') if not l.strip().startswith('#')]
                all_code += '\n'.join(lines) + '\n'

            clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
            clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
            
            # Checks
            if re.search(r'read_hdf|HDFStore', clean_code):
                method_score += 4
            if re.search(r'\.merge\s*\(|\.join\s*\(', clean_code):
                method_score += 4
            if re.search(r'quantile\s*\(\s*0?\.25\s*\)|percentile', clean_code):
                method_score += 5
            if re.search(r'sector_id.*(?:==\s*4|==\s*10|isin\s*\()', clean_code):
                method_score += 5
            if re.search(r'/\s*\(.*(?:\+\s*1|1\s*\+).*\)', clean_code):
                method_score += 5
            if re.search(r'>=\s*100|>\s*99', clean_code):
                method_score += 3
            if re.search(r'sort_values\s*\(.*ascending\s*=\s*False', clean_code) or re.search(r'nlargest', clean_code):
                method_score += 4

        except Exception as e:
            feedback.append(f"Failed to read notebook for deep analysis: {e}")
        finally:
            if os.path.exists(temp_nb.name):
                os.unlink(temp_nb.name)
                
    score += method_score
    feedback.append(f"Methodology: {method_score}/30")

    # CSV criteria (30 pts)
    csv_score = 0
    if result.get('csv_exists'):
        csv_score += 5
        if result.get('csv_created'):
            csv_score += 5
        if result.get('has_zone_id_col') and result.get('has_service_jobs_col') and result.get('has_low_income_hhs_col') and result.get('has_mismatch_ratio_col'):
            csv_score += 5
        if result.get('csv_rows') == 30:
            csv_score += 5
        if result.get('csv_top_ratio_valid'):
            csv_score += 10
            
    score += csv_score
    feedback.append(f"CSV Check: {csv_score}/30")

    # Plot criteria (20 pts)
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 10
        if result.get('plot_created'):
            plot_score += 5
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 5

    score += plot_score
    feedback.append(f"Plot Check: {plot_score}/20")

    # Final verdict
    passed = score >= 70 and result.get('csv_exists') and result.get('csv_rows', 0) > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }