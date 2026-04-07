#!/usr/bin/env python3
"""Verifier for empirical_employment_clustering_dbscan task."""

import json
import tempfile
import os
import re
import csv


def verify_employment_clustering(traj, env_info, task_info):
    """Verify DBSCAN employment clustering was run successfully.

    Scoring (100 points total):
    - Programmatic checks (20 pts): Notebook exists and modified, Plot exists
    - Code analysis (35 pts): proper parameters (eps=1500, min_samples=5), joins, filtering
    - Output validation (45 pts): CSV structure, absence of noise, descending sort by jobs
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # =========================================
    # Part 1: Task Result JSON (20 points)
    # =========================================
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

    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5
        feedback.append("Notebook correctly modified.")
    else:
        feedback.append("Notebook not modified.")

    if result.get('plot_exists') and result.get('plot_created'):
        score += 10
        if result.get('plot_size_kb', 0) >= 10:
            score += 5
            feedback.append("Valid cluster map plot created.")
        else:
            feedback.append("Cluster map plot exists but is too small.")
    else:
        feedback.append("Cluster map plot missing.")

    # =========================================
    # Part 2: Deep code analysis (35 pts)
    # =========================================
    temp_nb = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    try:
        copy_from_env(
            metadata.get('expected_notebook_path', '/home/ga/urbansim_projects/notebooks/employment_clustering.ipynb'),
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

        # Strip string literals to prevent gaming
        clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', all_code)
        clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)

        has_data_load = bool(re.search(r'read_hdf', clean_code))
        has_dbscan = bool(re.search(r'DBSCAN\s*\(', clean_code))
        has_eps_1500 = bool(re.search(r'eps\s*=\s*1500', clean_code))
        has_min_samples_5 = bool(re.search(r'min_samples\s*=\s*5', clean_code))
        has_threshold_50 = bool(re.search(r'>=\s*50|\s*50\s*<=', clean_code))
        has_noise_filter = bool(re.search(r'!=?\s*-1|>=\s*0|>[\s]*-[1-9]', clean_code))
        has_groupby = bool(re.search(r'groupby\s*\(', clean_code))

        if has_data_load: score += 5
        if has_dbscan: score += 5
        if has_eps_1500 and has_min_samples_5:
            score += 10
            feedback.append("Correct DBSCAN parameters found.")
        else:
            feedback.append("Incorrect or missing DBSCAN parameters (eps=1500, min_samples=5).")
            
        if has_threshold_50: score += 5
        if has_noise_filter: score += 5
        if has_groupby: score += 5

    except Exception as e:
        feedback.append(f"Error reading notebook logic: {e}")
    finally:
        if os.path.exists(temp_nb.name):
            os.unlink(temp_nb.name)

    # =========================================
    # Part 3: Output Validation (45 pts)
    # =========================================
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(
            metadata.get('expected_csv_path', '/home/ga/urbansim_projects/output/employment_clusters.csv'),
            temp_csv.name
        )
        
        if os.path.exists(temp_csv.name) and os.path.getsize(temp_csv.name) > 0:
            score += 10
            
            with open(temp_csv.name, 'r') as f:
                reader = csv.reader(f)
                header = next(reader, [])
                headers_lower = [h.lower().strip() for h in header]
                
                required_cols = ['building_count', 'total_jobs', 'centroid_x', 'centroid_y']
                cols_present = all(any(req in h for h in headers_lower) for req in required_cols)
                
                if cols_present:
                    score += 10
                    feedback.append("CSV contains required columns.")
                else:
                    feedback.append(f"CSV missing required columns. Found: {headers_lower}")
                
                # Check rows
                rows = list(reader)
                if len(rows) > 0:
                    score += 5
                    
                    # Validate sorting by total_jobs and absence of noise
                    try:
                        jobs_idx = next(i for i, h in enumerate(headers_lower) if 'total_jobs' in h)
                        
                        is_sorted = True
                        prev_jobs = float('inf')
                        has_noise = False
                        
                        for row in rows:
                            # If cluster index column contains -1
                            if row[0] == '-1' or row[0] == -1.0:
                                has_noise = True
                                
                            jobs_val = float(row[jobs_idx])
                            if jobs_val > prev_jobs:
                                is_sorted = False
                            prev_jobs = jobs_val
                            
                        if is_sorted:
                            score += 10
                            feedback.append("Clusters are properly sorted by total_jobs descending.")
                        else:
                            feedback.append("Clusters are NOT sorted by total_jobs descending.")
                            
                        if not has_noise:
                            score += 10
                            feedback.append("Noise points (-1) correctly filtered out.")
                        else:
                            feedback.append("Noise points (-1) found in final output CSV.")
                            
                    except Exception as e:
                        feedback.append(f"Could not parse row values properly: {e}")
                else:
                    feedback.append("CSV is empty.")
        else:
            feedback.append("CSV file not found or empty.")
            
    except Exception as e:
        feedback.append(f"Error analyzing CSV output: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 60 and result.get('csv_exists', False) and result.get('notebook_modified', False)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }