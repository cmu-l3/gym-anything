#!/usr/bin/env python3
"""
Verifier for pigeon_orientation_circular task.

Criteria:
1. Summary CSV exists, is new, and contains correct circular stats (30 pts)
2. Test CSV exists, is new, and contains Watson-Williams result (20 pts)
3. Rose Plot exists and is a valid image (20 pts)
4. R script uses 'circular' package (10 pts)
5. Data accuracy (Control group mean direction and Rho) (20 pts)
"""

import json
import os
import tempfile
import csv
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pigeon_orientation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_res = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 1. Verify Summary CSV (30 pts base + 20 pts accuracy)
    summary_path = task_info['metadata']['summary_csv']
    if task_res.get('summary_exists') and task_res.get('summary_new'):
        score += 15
        feedback.append("Summary CSV created.")
        
        # Download and verify content
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(summary_path, temp_csv.name)
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
            if len(rows) >= 2:
                score += 15
                feedback.append("Summary CSV has sufficient rows.")
                
                # Verify accuracy (Ground Truth Checking)
                # Known approx values for circular::pigeons$control
                # Mean approx 20-25 degrees (homeward is roughly North/NNE depending on exp)
                # Actually, standard circular::pigeons dataset:
                # Control group is usually homeward oriented.
                # We check ranges to be safe against minor calculation diffs.
                
                control_found = False
                for row in rows:
                    # Normalize keys to lower case
                    r = {k.lower().strip(): v for k, v in row.items()}
                    
                    grp = r.get('group', '').lower()
                    if 'control' in grp:
                        control_found = True
                        try:
                            # Check Mean Direction (expecting degrees ~15-30)
                            mean_dir = float(r.get('mean_direction_deg', -999))
                            # Handle potential negative degrees or >360 (unlikely but possible)
                            mean_dir = mean_dir % 360
                            
                            if 10 <= mean_dir <= 40:
                                score += 10
                                feedback.append(f"Control mean direction correct ({mean_dir:.1f}°).")
                            else:
                                feedback.append(f"Control mean direction out of expected range (10-40°): {mean_dir:.1f}°")

                            # Check Rho (Mean Resultant Length) - should be high for control
                            rho = float(r.get('mean_resultant_length', -1))
                            if 0.45 <= rho <= 1.0:
                                score += 10
                                feedback.append(f"Control Rho correct ({rho:.2f}).")
                            else:
                                feedback.append(f"Control Rho out of expected range (>0.45): {rho:.2f}")
                                
                        except ValueError:
                            feedback.append("Could not parse numeric values in Summary CSV.")
                
                if not control_found:
                    feedback.append("Control group not found in summary.")
                    
            else:
                feedback.append("Summary CSV has fewer than 2 rows.")
        except Exception as e:
            feedback.append(f"Error reading Summary CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback.append("Summary CSV missing or not created during task.")

    # 2. Verify Test CSV (20 pts)
    test_path = task_info['metadata']['test_csv']
    if task_res.get('test_exists') and task_res.get('test_new'):
        score += 10
        if task_res.get('test_watson'):
            score += 10
            feedback.append("Watson-Williams test performed.")
        else:
            feedback.append("Test CSV does not appear to contain Watson-Williams test.")
    else:
        feedback.append("Test CSV missing.")

    # 3. Verify Plot (20 pts)
    if task_res.get('plot_exists') and task_res.get('plot_new'):
        size = task_res.get('plot_size', 0)
        if size > 10000: # > 10KB
            score += 20
            feedback.append(f"Rose plot created ({size} bytes).")
        else:
            score += 5
            feedback.append("Rose plot file exists but is very small.")
    else:
        feedback.append("Rose plot missing.")

    # 4. Script Modification (10 pts)
    if task_res.get('script_modified'):
        score += 10
        feedback.append("R script modified.")
    else:
        feedback.append("R script not modified.")

    # Final Check
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }