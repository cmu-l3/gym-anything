#!/usr/bin/env python3
"""Verifier for active_transportation_propensity task."""

import json
import tempfile
import os
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for checking the trajectory
TRAJECTORY_VLM_PROMPT = """You are analyzing trajectory frames of an agent computing an Active Transportation Propensity Score.

Look at the provided sequence of screenshots and evaluate if the agent successfully completed the workflow.

Assess the following:
1. NOTEBOOK_WORK: Did the agent write and execute Python code in Jupyter Lab?
2. BAR_CHART_CREATED: Does the agent ever display a bar chart (either in the notebook output or final PNG) showing multiple components for zones?
3. WORKFLOW_COMPLETED: Did the agent seem to progress through data loading, merging, normalization, and charting?

Respond in JSON format:
{
    "notebook_work": true/false,
    "bar_chart_created": true/false,
    "workflow_completed": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_active_transportation_propensity(traj, env_info, task_info):
    """Verify active transportation propensity score task.
    
    Scoring Breakdown (100 points total):
    - Notebook Execution: 20 pts
    - Code Methodology (from JSON analysis): 15 pts
    - CSV Structure & Columns: 15 pts
    - Normalization Validity (0.0 to 1.0 bounds & sorted order): 20 pts
    - Ground Truth Alignment: 15 pts
    - Visualization Asset & VLM: 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # 1. Load task_result.json from container
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

    if result is None:
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 1: Notebook Execution (20 pts)
    nb_exec_score = 0
    if result.get('notebook_exists') and result.get('notebook_modified'):
        nb_exec_score += 5
    nb_a = result.get('notebook_analysis', {})
    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec >= 4:
        nb_exec_score += 15
    elif num_exec >= 1:
        nb_exec_score += 5
    score += nb_exec_score
    feedback.append(f"Notebook Exec: {nb_exec_score}/20")

    # Criterion 2: Code Methodology (15 pts)
    code_score = 0
    if nb_a.get('has_pandas') and nb_a.get('has_hdf'):
        code_score += 5
    if nb_a.get('has_merge') and nb_a.get('has_groupby'):
        code_score += 5
    if nb_a.get('has_normalization'):
        code_score += 5
    score += code_score
    feedback.append(f"Methodology: {code_score}/15")

    # Load Ground Truth
    gt_top_5 = []
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ground_truth_top5.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_top_5 = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 3 & 4. Evaluate CSV (Structure 15 pts, Normalization bounds 20 pts, GT 15 pts)
    csv_structure_score = 0
    norm_validity_score = 0
    gt_score = 0

    if result.get('csv_exists') and result.get('csv_created'):
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/home/ga/urbansim_projects/output/active_transit_scores.csv", temp_csv.name)
            
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                columns = reader.fieldnames if reader.fieldnames else []
                rows = list(reader)
                
            cols_lower = [c.lower() for c in columns]
            
            # Structure check
            has_norm = all(c in cols_lower for c in metadata.get('required_norm_columns', []))
            has_score = metadata.get('score_column', 'atp_score') in cols_lower
            has_filters = any('parcel' in c for c in cols_lower) and any('house' in c or 'hh' in c for c in cols_lower)
            
            if has_norm and has_score:
                csv_structure_score += 10
            if has_filters:
                csv_structure_score += 5
                
            # Validity check
            if len(rows) > 0 and has_norm and has_score:
                valid_bounds = True
                valid_filtering = True
                valid_math = True
                is_sorted = True
                
                prev_score = float('inf')
                agent_top_5 = []
                
                for idx, row in enumerate(rows):
                    try:
                        # Extract metrics
                        norm1 = float(row.get('hh_density_norm', 0))
                        norm2 = float(row.get('job_density_norm', 0))
                        norm3 = float(row.get('zero_car_pct_norm', 0))
                        row_score = float(row.get('atp_score', 0))
                        
                        # Bounds [0, 1]
                        if not (0.0 <= norm1 <= 1.0 and 0.0 <= norm2 <= 1.0 and 0.0 <= norm3 <= 1.0):
                            valid_bounds = False
                            
                        # Math check (avg)
                        expected_score = (norm1 + norm2 + norm3) / 3.0
                        if not math.isclose(row_score, expected_score, abs_tol=0.01):
                            valid_math = False
                            
                        # Sort check
                        if row_score > prev_score + 0.001:
                            is_sorted = False
                        prev_score = row_score
                        
                        # Filter check (if columns present)
                        p_count_col = next((c for c in row if 'parcel_count' in c.lower()), None)
                        hh_col = next((c for c in row if 'total_households' in c.lower()), None)
                        if p_count_col and hh_col:
                            if float(row[p_count_col]) < 50 or float(row[hh_col]) == 0:
                                valid_filtering = False

                        if idx < 5:
                            # Try to extract zone ID
                            zone_col = next((c for c in row if 'zone' in c.lower()), None)
                            if zone_col:
                                agent_top_5.append(int(float(row[zone_col])))
                    except ValueError:
                        pass
                
                if valid_bounds: norm_validity_score += 10
                if valid_math: norm_validity_score += 5
                if is_sorted: norm_validity_score += 5
                if not valid_filtering: norm_validity_score -= 5 # Penalty
                
                # Ground truth check
                if gt_top_5 and agent_top_5:
                    matches = len(set(gt_top_5).intersection(set(agent_top_5)))
                    if matches >= 3:
                        gt_score += 15
                    elif matches >= 1:
                        gt_score += 7

        except Exception as e:
            logger.warning(f"Error evaluating CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
                
    score += csv_structure_score
    score += norm_validity_score
    score += gt_score
    feedback.append(f"CSV Structure: {csv_structure_score}/15")
    feedback.append(f"Norm Bounds: {norm_validity_score}/20")
    feedback.append(f"Ground Truth: {gt_score}/15")

    # Criterion 6: Visualization Asset & VLM (15 pts)
    vis_score = 0
    if result.get('plot_exists') and result.get('plot_created'):
        vis_score += 5
        if result.get('plot_size_kb', 0) >= 15:
            vis_score += 5
            
    # Trajectory VLM Check
    try:
        from vlm_utils import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=TRAJECTORY_VLM_PROMPT)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("notebook_work"):
                    vis_score += 2
                if parsed.get("bar_chart_created"):
                    vis_score += 3
    except ImportError:
        logger.warning("VLM utilities not available.")
    except Exception as e:
        logger.warning(f"VLM evaluation failed: {e}")

    # Cap vis_score at 15
    vis_score = min(vis_score, 15)
    score += vis_score
    feedback.append(f"Visualizations: {vis_score}/15")

    # Final tally
    passed = score >= 70 and csv_structure_score >= 10 and norm_validity_score >= 15
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }