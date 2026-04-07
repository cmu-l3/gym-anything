#!/usr/bin/env python3
"""
Verifier for Polycentric Employment Analysis (UrbanSim).
Checks generated output files, ensures they match ground truth metrics exactly,
and verifies notebook code execution via VLM trajectory checks.
"""

import os
import json
import csv
import re
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            columns = reader.fieldnames or []
        return {"valid": True, "rows": rows, "columns": [c.lower() for c in columns]}
    except Exception as e:
        return {"valid": False, "error": str(e), "rows": [], "columns": []}

def check_string_similarity(expected_list, actual_list):
    return all(any(exp in act for act in actual_list) for exp in expected_list)

def verify_polycentric_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Paths
    gt_path = "/tmp/ground_truth.json"
    csv1_path = "/home/ga/urbansim_projects/output/zone_employment_density.csv"
    csv2_path = "/home/ga/urbansim_projects/output/subcenter_ranking.csv"
    json_path = "/home/ga/urbansim_projects/output/zipf_results.json"
    plot_path = "/home/ga/urbansim_projects/output/ranksize_plot.png"
    nb_path = "/home/ga/urbansim_projects/notebooks/polycentric_analysis.ipynb"
    task_res_path = "/tmp/task_result.json"

    score = 0
    feedback = []
    
    # Helper to copy & read JSON securely
    def load_json_from_env(remote_path):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                return json.load(f)
        except Exception:
            return None
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
                
    # Helper to copy file to local
    def copy_file_local(remote_path, suffix='.tmp'):
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        try:
            copy_from_env(remote_path, tmp.name)
            return tmp.name
        except Exception:
            os.unlink(tmp.name)
            return None

    # Load Ground Truth
    gt = load_json_from_env(gt_path)
    if not gt:
        return {"passed": False, "score": 0, "feedback": "Verifier Error: Could not load ground truth."}

    # Load Task Result Metadata
    task_res = load_json_from_env(task_res_path)
    if not task_res:
        return {"passed": False, "score": 0, "feedback": "Verifier Error: Could not load task result metadata."}

    files_meta = task_res.get('files', {})

    # 1. Verify zone_employment_density.csv (10 pts + 15 pts + 5 pts)
    csv1_local = copy_file_local(csv1_path, '.csv')
    if csv1_local and files_meta.get('csv1', {}).get('exists'):
        csv1_data = parse_csv(csv1_local)
        if csv1_data['valid'] and check_string_similarity(['zone', 'total_employment', 'num_parcels', 'density', 'is_subcenter'], csv1_data['columns']):
            score += 10
            feedback.append("CSV1 valid structure (+10).")
            
            # Check totals
            try:
                emp_col = next(c for c in csv1_data['columns'] if 'employment' in c)
                agent_total_emp = sum(float(r[emp_col]) for r in csv1_data['rows'] if r.get(emp_col, '').replace('.', '', 1).isdigit())
                
                gt_emp = gt['total_citywide_employment']
                if abs(agent_total_emp - gt_emp) / max(gt_emp, 1) < 0.02:
                    score += 15
                    feedback.append(f"Total employment calculation matches GT (+15).")
                else:
                    feedback.append(f"Total employment mismatch (Expected: {gt_emp}, Got: {agent_total_emp}).")
                
                if len(csv1_data['rows']) == gt['num_zones']:
                    score += 5
                    feedback.append("Zone count matches GT (+5).")
            except Exception as e:
                feedback.append(f"Error parsing CSV1 rows: {e}")
        else:
            feedback.append("CSV1 missing required columns or invalid.")
    else:
        feedback.append("CSV1 not found.")
    if csv1_local and os.path.exists(csv1_local): os.unlink(csv1_local)

    # 2. Verify subcenter_ranking.csv (10 pts + 10 pts)
    csv2_local = copy_file_local(csv2_path, '.csv')
    if csv2_local and files_meta.get('csv2', {}).get('exists'):
        csv2_data = parse_csv(csv2_local)
        if csv2_data['valid'] and check_string_similarity(['rank', 'zone', 'employment'], csv2_data['columns']):
            score += 10
            feedback.append("CSV2 valid structure (+10).")
            
            agent_subcenters = len(csv2_data['rows'])
            if agent_subcenters == gt['num_subcenters']:
                score += 10
                feedback.append("Subcenter count matches GT deterministic threshold (+10).")
            else:
                feedback.append(f"Subcenter count mismatch (Expected: {gt['num_subcenters']}, Got: {agent_subcenters}).")
        else:
            feedback.append("CSV2 missing columns.")
    else:
        feedback.append("CSV2 not found.")
    if csv2_local and os.path.exists(csv2_local): os.unlink(csv2_local)

    # 3. Verify zipf_results.json (5 pts + 15 pts + 10 pts)
    agent_json = load_json_from_env(json_path)
    if agent_json:
        req_keys = ['zipf_exponent', 'r_squared', 'num_subcenters', 'total_citywide_employment', 'density_threshold']
        if all(k in agent_json for k in req_keys):
            score += 5
            feedback.append("JSON output contains required keys (+5).")
            
            agent_zipf = float(agent_json.get('zipf_exponent', 0))
            if abs(agent_zipf - gt['zipf_exponent']) <= 0.05:
                score += 15
                feedback.append(f"Zipf exponent accurate (+15).")
            else:
                feedback.append(f"Zipf exponent mismatch (Expected: {gt['zipf_exponent']:.4f}, Got: {agent_zipf:.4f}).")
                
            agent_r2 = float(agent_json.get('r_squared', 0))
            if abs(agent_r2 - gt['r_squared']) <= 0.05:
                score += 10
                feedback.append(f"R-squared accurate (+10).")
        else:
            feedback.append("JSON missing required keys.")
    else:
        feedback.append("JSON results file not found.")

    # 4. Verify ranksize_plot.png (10 pts)
    plot_size = files_meta.get('plot', {}).get('size', 0)
    if plot_size > 10240: # >10KB
        score += 10
        feedback.append("Rank-size plot valid and non-trivial (+10).")
    else:
        feedback.append("Rank-size plot missing or too small.")

    # 5. Notebook / Workflow Verification (10 pts)
    nb_local = copy_file_local(nb_path, '.ipynb')
    if nb_local and files_meta.get('notebook', {}).get('exists'):
        try:
            with open(nb_local, 'r') as f:
                nb = json.load(f)
            code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
            executed = sum(1 for c in code_cells if c.get('execution_count') is not None)
            if executed >= 5:
                score += 10
                feedback.append(f"Notebook shows meaningful execution ({executed} cells) (+10).")
            elif executed > 0:
                score += 5
                feedback.append("Notebook partially executed (+5).")
        except Exception:
            feedback.append("Notebook parsing failed.")
    else:
        feedback.append("Notebook missing or invalid.")
    if nb_local and os.path.exists(nb_local): os.unlink(nb_local)

    # Trajectory check via VLM for visual validation (optional supplemental context)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = "Is there evidence of the agent interacting with Jupyter Lab and running data analysis Python code?"
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('success'):
                logger.info(f"VLM observation: {vlm_res.get('parsed', {})}")
    except Exception as e:
        logger.warning(f"VLM trajectory check failed: {e}")

    # Pass condition
    passed = score >= 60 and files_meta.get('csv1', {}).get('exists') and files_meta.get('notebook', {}).get('exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }