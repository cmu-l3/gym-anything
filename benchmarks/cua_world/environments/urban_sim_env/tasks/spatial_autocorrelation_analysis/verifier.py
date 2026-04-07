#!/usr/bin/env python3
"""Verifier for spatial_autocorrelation_analysis task."""

import json
import tempfile
import os
import re
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_autocorrelation(traj, env_info, task_info):
    """Verify that spatial autocorrelation analysis was correctly performed.
    
    Total: 100 points (Pass Threshold: 60)
    - Notebook Code & Execution: 25 pts
    - CSV File validation: 20 pts
    - PNG Map validation: 10 pts
    - Summary JSON + GT validation: 25 pts
    - VLM Trajectory Process: 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # 1. READ TASK EXPORT METADATA
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_meta = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        feedback.append(f"Failed to read result metadata: {e}")
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # 2. EVALUATE NOTEBOOK (25 pts)
    temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    nb_score = 0
    try:
        copy_from_env(metadata.get('expected_notebook_path', '/home/ga/urbansim_projects/notebooks/spatial_autocorrelation.ipynb'), temp_nb.name)
        with open(temp_nb.name, 'r') as f:
            nb = json.load(f)
            
        code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
        num_executed = sum(1 for c in code_cells if c.get('execution_count') is not None)
        if num_executed >= 3:
            nb_score += 5
            feedback.append("Notebook executed successfully.")
            
        all_code = ''
        for cell in code_cells:
            src = cell.get('source', '')
            if isinstance(src, list): src = ''.join(src)
            all_code += src + '\n'
            
        # Strip strings to prevent keyword gaming
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
        
        has_load = bool(re.search(r'read_hdf|read_file|HDFStore', clean_code))
        has_merge = bool(re.search(r'\.merge\s*\(|\.join\s*\(', clean_code))
        has_weights = bool(re.search(r'Queen|weights', clean_code))
        has_moran = bool(re.search(r'Moran\s*\(|Moran_Local\s*\(', clean_code))
        
        if has_load: nb_score += 5
        if has_merge: nb_score += 5
        if has_weights: nb_score += 5
        if has_moran: nb_score += 5
        
        score += nb_score
        feedback.append(f"Notebook code score: {nb_score}/25")
    except Exception as e:
        feedback.append(f"Notebook verification failed: {e}")
    finally:
        if os.path.exists(temp_nb.name): os.unlink(temp_nb.name)

    # 3. EVALUATE CSV (20 pts)
    csv_meta = result_meta.get('csv', {})
    csv_score = 0
    if csv_meta.get('exists') and csv_meta.get('created_during_task'):
        csv_score += 5
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/lisa_results.csv'), temp_csv.name)
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                headers = [h.strip().lower() for h in (reader.fieldnames or [])]
                expected = ['zone_id', 'residential_units', 'local_morans_i', 'p_value', 'cluster_type']
                if all(c in headers for c in expected):
                    csv_score += 5
                
                rows = list(reader)
                if len(rows) > 10:
                    csv_score += 5
                    
                valid_types = {'HH', 'LL', 'HL', 'LH', 'NS'}
                valid_clusters = True
                for row in rows[:50]:
                    cluster = row.get('cluster_type', '').strip()
                    if cluster not in valid_types:
                        valid_clusters = False
                        break
                if valid_clusters and len(rows) > 0:
                    csv_score += 5
            score += csv_score
            feedback.append(f"CSV score: {csv_score}/20")
        except Exception as e:
            feedback.append(f"CSV parsing error: {e}")
        finally:
            if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)
    else:
        feedback.append("CSV not created or invalid.")

    # 4. EVALUATE PNG MAP (10 pts)
    png_meta = result_meta.get('png', {})
    if png_meta.get('exists') and png_meta.get('created_during_task') and png_meta.get('size_kb') >= 5:
        score += 10
        feedback.append("PNG map created and valid size.")
    else:
        feedback.append("PNG map missing or invalid.")

    # 5. EVALUATE SUMMARY JSON & GROUND TRUTH (25 pts)
    json_score = 0
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        json_meta = result_meta.get('json', {})
        if json_meta.get('exists') and json_meta.get('created_during_task'):
            json_score += 5
            
            copy_from_env(metadata.get('expected_json_path', '/home/ga/urbansim_projects/output/spatial_summary.json'), temp_json.name)
            with open(temp_json.name, 'r') as f:
                user_json = json.load(f)
                
            expected_keys = ['global_morans_i', 'global_p_value', 'num_zones', 'count_HH', 'count_LL', 'count_HL', 'count_LH', 'count_NS']
            if all(k in user_json for k in expected_keys):
                json_score += 5
                
                # Fetch Ground Truth
                copy_from_env('/tmp/ground_truth/spatial_truth.json', temp_gt.name)
                with open(temp_gt.name, 'r') as f:
                    gt_json = json.load(f)
                    
                gt_moran = gt_json.get('global_morans_i')
                user_moran = user_json.get('global_morans_i')
                
                if gt_moran is not None and user_moran is not None:
                    if isinstance(user_moran, (int, float)) and abs(gt_moran - user_moran) < 0.05:
                        json_score += 15
                        feedback.append(f"Moran's I correctly calculated: {user_moran:.4f}")
                    else:
                        feedback.append(f"Moran's I mismatch. Expected ~{gt_moran}, got {user_moran}")
        score += json_score
        feedback.append(f"JSON Output & Math score: {json_score}/25")
    except Exception as e:
        feedback.append(f"JSON validation error: {e}")
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    # 6. VLM TRAJECTORY VERIFICATION (20 pts)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and frames and final:
            prompt = """You are evaluating an agent performing Spatial Autocorrelation Analysis in JupyterLab.
Look at the sequence of frames and the final screenshot. 
Assess:
1. Did the agent write/run Python code for spatial statistics (e.g., using esda, libpysal, Moran)?
2. Is there a visual map or choropleth showing clusters/zoning?
Answer with valid JSON: {"has_code": true/false, "has_map": true/false}
"""
            res = query_vlm(prompt=prompt, images=frames + [final])
            if res and res.get('success'):
                parsed = res.get('parsed', {})
                if parsed.get('has_code'): vlm_score += 10
                if parsed.get('has_map'): vlm_score += 10
            else:
                # VLM failed logic, fallback to programmatic indication
                if score >= 50: vlm_score = 20
        else:
            if score >= 50: vlm_score = 20
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        if score >= 50: vlm_score = 20
        
    score += vlm_score
    feedback.append(f"VLM score: {vlm_score}/20")

    passed = score >= 60 and (csv_score > 0 or json_score > 0)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }