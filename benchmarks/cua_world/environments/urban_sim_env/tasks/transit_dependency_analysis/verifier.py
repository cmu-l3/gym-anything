#!/usr/bin/env python3
"""Verifier for transit_dependency_analysis task."""

import json
import tempfile
import os
import re
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transit_dependency(traj, env_info, task_info):
    """
    Verify the household vehicle ownership analysis task.

    Scoring (100 points total):
    - 10 pts: Notebook exists and executed
    - 15 pts: Code patterns valid (join, groupby, plot)
    - 15 pts: CSV structure (has all expected columns)
    - 15 pts: CSV content (plausible values, >=10 zones)
    - 10 pts: Transit-dependent correctly flagged
    - 30 pts: PNGs exist and valid (10 pts per PNG)
    -  5 pts: VLM Trajectory Verification
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cols = [c.lower() for c in metadata.get('expected_csv_columns', [])]
    
    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # 1. Load the task_result.json exported by the bash script
    # ---------------------------------------------------------
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ---------------------------------------------------------
    # 2. Score Notebook Execution and Code Analysis (25 pts)
    # ---------------------------------------------------------
    nb_executed = False
    if result.get('notebook_exists'):
        nb_a = result.get('notebook_analysis', {})
        executed_cells = nb_a.get('num_executed_cells', 0)
        
        if executed_cells >= 5:
            score += 10
            nb_executed = True
            feedback.append("Notebook properly executed")
        elif executed_cells > 0:
            score += 5
            feedback.append("Notebook partially executed")
        else:
            feedback.append("Notebook contains no executed cells")

        # Code patterns (15 pts)
        patterns_score = 0
        if nb_a.get('has_read_hdf'): patterns_score += 3
        if nb_a.get('has_merge'): patterns_score += 4
        if nb_a.get('has_groupby'): patterns_score += 4
        if nb_a.get('has_plot') or nb_a.get('has_to_csv'): patterns_score += 4
        
        score += patterns_score
        feedback.append(f"Code patterns detected ({patterns_score}/15)")

    # ---------------------------------------------------------
    # 3. Score CSV Structure & Content (40 pts)
    # ---------------------------------------------------------
    csv_exists = result.get('csv_exists', False)
    csv_created = result.get('csv_created_during_task', False)
    
    if csv_exists and csv_created:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(metadata.get('expected_csv_path'), temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                cols = [c.lower().strip() for c in reader.fieldnames or []]
                
                # Check CSV Structure (15 pts)
                has_all_cols = all(expected in cols for expected in expected_cols)
                if has_all_cols:
                    score += 10
                    feedback.append("CSV has all required columns")
                else:
                    score += 5
                    feedback.append("CSV missing some required columns")
                    
                if len(rows) >= 10:
                    score += 5
                
                # Check CSV Content and Ranges (15 pts)
                valid_pct = 0
                valid_cars = 0
                valid_income = 0
                transit_flagged = False
                
                for row in rows:
                    # Find keys dynamically due to potential whitespace or exact casing
                    row_lower = {k.lower().strip(): v for k, v in row.items() if k}
                    
                    try:
                        pct = float(row_lower.get('pct_zero_car', -1))
                        if 0 <= pct <= 100: valid_pct += 1
                        
                        cars = float(row_lower.get('mean_cars', -1))
                        if 0 <= cars <= 10: valid_cars += 1
                        
                        inc = float(row_lower.get('median_income', -1))
                        if inc > 0: valid_income += 1
                        
                        flag = str(row_lower.get('transit_dependent', '')).lower()
                        if (flag in ['true', '1', 'yes'] or flag == '1.0') and pct > 30:
                            transit_flagged = True
                    except Exception:
                        pass
                
                content_score = 0
                if valid_pct > 0: content_score += 5
                if valid_cars > 0: content_score += 5
                if valid_income > 0: content_score += 5
                
                score += content_score
                feedback.append(f"CSV values plausible ({content_score}/15)")
                
                # Transit dependency correctly flagged (10 pts)
                if transit_flagged:
                    score += 10
                    feedback.append("Transit-dependent zones successfully flagged")
                else:
                    feedback.append("Transit-dependent zones not properly flagged")
                    
        except Exception as e:
            logger.error(f"Error parsing CSV: {e}")
            feedback.append("Failed to validate CSV contents")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback.append("Output CSV not found or not created during task")

    # ---------------------------------------------------------
    # 4. Score PNG Visualizations (30 pts)
    # ---------------------------------------------------------
    min_kb = metadata.get('min_plot_size_kb', 5)
    
    pngs = [
        ("png1", "Histogram"),
        ("png2", "Scatter"),
        ("png3", "Bar Chart")
    ]
    
    for key, name in pngs:
        if result.get(f"{key}_exists") and result.get(f"{key}_created"):
            size_kb = result.get(f"{key}_size", 0) / 1024
            if size_kb >= min_kb:
                score += 10
                feedback.append(f"{name} PNG valid")
            else:
                score += 5
                feedback.append(f"{name} PNG exists but size is suspiciously small")
        else:
            feedback.append(f"{name} PNG not found")

    # ---------------------------------------------------------
    # 5. VLM Trajectory Verification (5 pts)
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames showing the workflow
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are evaluating an AI agent using Jupyter Lab to do UrbanSim data analysis.
            Look at this sequence of screenshots taken over time.
            Do you see clear progression of the agent writing Python code in a notebook, executing cells, 
            and generating either data tables or plots/charts?
            Answer strictly in JSON format: {"workflow_progressed": true/false}"""
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("workflow_progressed"):
                    vlm_score = 5
                    feedback.append("VLM verified meaningful workflow progression")
                else:
                    feedback.append("VLM did not observe meaningful workflow progression")
    except ImportError:
        logger.warning("VLM module not available, skipping VLM check.")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")

    score += vlm_score

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    passed = score >= 60 and nb_executed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }