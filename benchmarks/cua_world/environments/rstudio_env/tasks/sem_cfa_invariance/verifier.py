#!/usr/bin/env python3
"""
Verifier for SEM CFA Invariance Task.
"""

import json
import tempfile
import os
import csv
import logging

logger = logging.getLogger(__name__)

def verify_sem_cfa(traj, env_info, task_info):
    """
    Verify the SEM CFA task outputs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Helper to copy file from env to temp local file
    def get_file_content(container_path):
        if not container_path: return None
        tf = tempfile.NamedTemporaryFile(delete=False)
        tf.close()
        try:
            copy_from_env(container_path, tf.name)
            return tf.name
        except Exception:
            if os.path.exists(tf.name):
                os.unlink(tf.name)
            return None

    # Load result metadata
    result_json_path = get_file_content("/tmp/task_result.json")
    if not result_json_path:
        return {"passed": False, "score": 0, "feedback": "No result metadata found"}
    
    with open(result_json_path, 'r') as f:
        result = json.load(f)
    os.unlink(result_json_path)

    score = 0
    feedback = []
    files = result.get('files', {})

    # 1. Fit Statistics CSV (25 pts)
    fit_info = files.get('fit_stats', {})
    if fit_info.get('exists') and fit_info.get('is_new'):
        local_fit = get_file_content(fit_info['path'])
        if local_fit:
            try:
                with open(local_fit, 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    
                    # Normalize keys to lowercase
                    data = {}
                    for row in rows:
                        # Attempt to find statistic name and value
                        k = next((v for k,v in row.items() if 'stat' in k.lower()), None)
                        v = next((v for k,v in row.items() if 'val' in k.lower()), None)
                        if k and v:
                            data[k.lower()] = float(v)
                    
                    # Check values
                    cfi = data.get('cfi', 0)
                    rmsea = data.get('rmsea', 0)
                    
                    if 0.88 <= cfi <= 0.98:
                        score += 15
                        feedback.append(f"CFI is reasonable ({cfi:.3f})")
                    else:
                        feedback.append(f"CFI out of expected range ({cfi:.3f})")
                        
                    if 0.05 <= rmsea <= 0.15:
                        score += 10
                        feedback.append(f"RMSEA is reasonable ({rmsea:.3f})")
                    else:
                        feedback.append(f"RMSEA out of expected range ({rmsea:.3f})")

            except Exception as e:
                feedback.append(f"Error parsing fit stats: {e}")
            finally:
                os.unlink(local_fit)
    else:
        feedback.append("Fit statistics CSV missing or old")

    # 2. Factor Loadings CSV (20 pts)
    loadings_info = files.get('loadings', {})
    if loadings_info.get('exists') and loadings_info.get('is_new'):
        local_load = get_file_content(loadings_info['path'])
        if local_load:
            try:
                with open(local_load, 'r') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    if len(rows) >= 9:
                        score += 10
                        feedback.append("Factor loadings table has sufficient rows")
                    
                    # check for specific loading strength (e.g., x4 on Textual is usually high)
                    high_loadings = 0
                    for row in rows:
                        # Find loading value column
                        val_key = next((k for k in row.keys() if 'load' in k.lower() or 'est' in k.lower()), None)
                        if val_key:
                            try:
                                if abs(float(row[val_key])) > 0.6:
                                    high_loadings += 1
                            except: pass
                    
                    if high_loadings >= 3:
                        score += 10
                        feedback.append("Found strong factor loadings")
                    else:
                        feedback.append("Factor loadings seem too low")
            except Exception:
                feedback.append("Error parsing loadings CSV")
            finally:
                os.unlink(local_load)
    else:
        feedback.append("Factor loadings CSV missing")

    # 3. Measurement Invariance CSV (25 pts)
    inv_info = files.get('invariance', {})
    if inv_info.get('exists') and inv_info.get('is_new'):
        local_inv = get_file_content(inv_info['path'])
        if local_inv:
            try:
                with open(local_inv, 'r') as f:
                    content = f.read().lower()
                    if 'configural' in content and 'metric' in content:
                        score += 15
                        feedback.append("Invariance table contains expected models")
                    else:
                        feedback.append("Invariance table missing model names")
                    
                    # Check for numeric data
                    if any(c.isdigit() for c in content):
                        score += 10
                        feedback.append("Invariance table contains data")
            except Exception:
                feedback.append("Error reading invariance CSV")
            finally:
                os.unlink(local_inv)
    else:
        feedback.append("Measurement invariance CSV missing")

    # 4. Path Diagram (15 pts)
    diag_info = files.get('diagram', {})
    if diag_info.get('exists') and diag_info.get('is_new'):
        if diag_info.get('size', 0) > 10000: # >10KB
            score += 15
            feedback.append("Path diagram exists and has content")
        else:
            score += 5
            feedback.append("Path diagram exists but is very small")
    else:
        feedback.append("Path diagram missing")

    # 5. R Script (15 pts)
    script_info = files.get('script', {})
    if script_info.get('exists'):
        local_script = get_file_content(script_info['path'])
        if local_script:
            try:
                with open(local_script, 'r') as f:
                    content = f.read()
                    if 'lavaan' in content and 'cfa(' in content:
                        score += 15
                        feedback.append("R script contains lavaan code")
                    elif 'lavaan' in content:
                        score += 10
                        feedback.append("R script imports lavaan")
            finally:
                os.unlink(local_script)
    else:
        feedback.append("R script missing")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }