#!/usr/bin/env python3
"""Verifier for Building Vintage Cohort Analysis task.
Requires the framework to provide gym_anything.vlm helpers if available.
Uses copy_from_env to safely retrieve artifacts from the container.
"""

import json
import os
import re
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_vlm_feedback(traj, expected_csv_cols):
    """Fallback VLM check to visually verify the chart and process."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        
        prompt = """You are evaluating an AI agent's performance in analyzing urban building data in Jupyter Lab.
        
        Examine the provided screenshots (chronological trajectory + final state).
        Has the agent successfully:
        1. Executed a Jupyter notebook analyzing building construction years?
        2. Produced a stacked bar chart visualization of building vintage cohorts?
        3. Displayed signs of data aggregation (e.g. dataframes with percentages or building counts per zone)?
        
        Respond in strict JSON:
        {
            "notebook_visible": true/false,
            "stacked_chart_created": true/false,
            "data_aggregated": true/false,
            "confidence": "high/medium/low",
            "reasoning": "Brief explanation"
        }"""
        
        result = query_vlm(prompt=prompt, images=frames + [final_frame])
        if result and result.get('success'):
            return result.get('parsed', {})
    except ImportError:
        logger.warning("VLM module not available, skipping VLM check.")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        
    return None


def verify_building_vintage(traj, env_info, task_info):
    """
    Verification strategy:
    1. Read task_result.json & ground_truth.json using copy_from_env
    2. Inspect notebook content (code cells, execution state)
    3. Validate CSV correctness (schema, size, value matching against ground truth)
    4. Validate PNG chart existence and size
    5. Fallback/augment with VLM analysis on trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in env_info"}

    metadata = task_info.get('metadata', {})
    expected_cols = metadata.get('required_csv_columns', ['zone_id', 'total_buildings', 'pre_1940_count', 'pre_1940_pct', 'median_year_built'])

    score = 0
    feedback = []
    
    # 1. Load exported state
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
        tmp_result_path = f.name
    try:
        copy_from_env("/tmp/task_result.json", tmp_result_path)
        with open(tmp_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        os.unlink(tmp_result_path)

    # 2. Load Ground Truth
    gt_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as f:
        tmp_gt_path = f.name
    try:
        copy_from_env("/tmp/ground_truth/vintage_ground_truth.json", tmp_gt_path)
        with open(tmp_gt_path, 'r') as f:
            gt_data = json.load(f)
    except Exception:
        logger.warning("Ground truth file missing or unreadable.")
    finally:
        os.unlink(tmp_gt_path)

    # 3. Assess Notebook Code
    nb_score = 0
    with tempfile.NamedTemporaryFile(suffix='.ipynb', delete=False) as f:
        tmp_nb_path = f.name
    
    if result.get('notebook_modified', False):
        try:
            copy_from_env(metadata.get('expected_notebook_path', "/home/ga/urbansim_projects/notebooks/building_vintage_analysis.ipynb"), tmp_nb_path)
            with open(tmp_nb_path, 'r') as f:
                nb = json.load(f)
                
            code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
            num_executed = sum(1 for c in code_cells if c.get('execution_count') is not None)
            
            # Extract raw code, strip string literals to prevent keyword gaming
            raw_code = "\n".join(["".join(c.get('source', [])) for c in code_cells])
            clean_code = re.sub(r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'', '', raw_code)
            clean_code = re.sub(r'"[^"\n]*"|\'[^\'\n]*\'', '', clean_code)
            
            if num_executed >= 4:
                nb_score += 10
                feedback.append(f"Notebook adequately executed ({num_executed} cells).")
            elif num_executed > 0:
                nb_score += 5
                feedback.append(f"Notebook partially executed ({num_executed} cells).")
                
            # Code pattern checks
            if re.search(r'read_hdf|HDFStore', clean_code): nb_score += 3
            if re.search(r'merge|join', clean_code): nb_score += 3
            if re.search(r'groupby', clean_code): nb_score += 3
            if re.search(r'1940|1960|1980|2000', clean_code): nb_score += 3
            if re.search(r'to_csv', clean_code): nb_score += 1.5
            if re.search(r'savefig', clean_code): nb_score += 1.5

        except Exception as e:
            feedback.append(f"Error analyzing notebook: {e}")
    else:
        feedback.append("Notebook was not created/modified during task.")
    
    if os.path.exists(tmp_nb_path):
        os.unlink(tmp_nb_path)
        
    score += nb_score

    # 4. Assess CSV Output
    csv_score = 0
    if result.get('csv_modified', False):
        feedback.append("CSV file generated.")
        
        # Check columns
        csv_cols = result.get('csv_columns', [])
        missing_cols = [c for c in expected_cols if c not in csv_cols]
        if not missing_cols:
            csv_score += 10
            feedback.append("CSV schema perfectly matches expectations.")
        else:
            matched = len(expected_cols) - len(missing_cols)
            csv_score += (10 * (matched / len(expected_cols)))
            feedback.append(f"CSV missing columns: {missing_cols}")

        # Check rows count (should be ~10)
        rows = result.get('csv_rows', 0)
        if 8 <= rows <= 12:
            csv_score += 10
            feedback.append(f"CSV has correct row count ({rows}).")
        elif rows > 0:
            csv_score += 5
            feedback.append(f"CSV row count is {rows} (expected 10).")
            
        # Ground Truth Overlap (If available, check zone ids)
        gt_zones = set(gt_data.get('top10_zone_ids', []))
        if gt_zones:
            # We must copy and read the CSV to check overlap
            with tempfile.NamedTemporaryFile(suffix='.csv', delete=False) as f:
                tmp_csv_path = f.name
            try:
                copy_from_env(metadata.get('expected_csv_path', "/home/ga/urbansim_projects/output/aging_building_zones.csv"), tmp_csv_path)
                with open(tmp_csv_path, 'r') as f:
                    reader = csv.DictReader(f)
                    agent_zones = set()
                    for row in reader:
                        # find the zone_id key (ignoring exact case)
                        z_key = next((k for k in row.keys() if 'zone_id' in str(k).lower() or 'zoning_id' in str(k).lower()), None)
                        if z_key and row[z_key].strip().isdigit():
                            agent_zones.add(int(float(row[z_key].strip())))
                    
                    overlap = len(gt_zones.intersection(agent_zones))
                    if overlap >= 8:
                        csv_score += 15
                        feedback.append(f"High ground truth overlap ({overlap}/10 zones).")
                    elif overlap >= 5:
                        csv_score += 10
                        feedback.append(f"Moderate ground truth overlap ({overlap}/10 zones).")
                    elif overlap > 0:
                        csv_score += 5
                        feedback.append(f"Low ground truth overlap ({overlap}/10 zones).")
                    else:
                        feedback.append("No overlap with ground truth zones.")
            except Exception as e:
                logger.error(f"Error checking CSV ground truth: {e}")
            finally:
                if os.path.exists(tmp_csv_path):
                    os.unlink(tmp_csv_path)
        else:
            # Without ground truth, grant partial fallback credit
            csv_score += 10
    else:
        feedback.append("CSV file not created or modified.")
        
    score += csv_score

    # 5. Assess PNG Chart Output
    chart_score = 0
    if result.get('chart_modified', False):
        size_kb = result.get('chart_size_kb', 0)
        if size_kb >= 10:
            chart_score += 20
            feedback.append(f"Chart saved successfully ({size_kb:.1f} KB).")
        elif size_kb > 0:
            chart_score += 10
            feedback.append(f"Chart saved but is unusually small ({size_kb:.1f} KB).")
    else:
        feedback.append("Chart PNG not created or modified.")
        
    score += chart_score

    # 6. Optional VLM Verification (Trajectory checking)
    vlm_res = get_vlm_feedback(traj, expected_cols)
    if vlm_res:
        vlm_score = 0
        if vlm_res.get('stacked_chart_created'):
            vlm_score += 10
            feedback.append("VLM confirms stacked chart creation.")
        if vlm_res.get('data_aggregated'):
            vlm_score += 5
            feedback.append("VLM confirms data aggregation process.")
        score += vlm_score

    # Normalize score to max 100
    score = min(int(score), 100)
    
    # Requirement for passing: Must have some notebook execution + CSV or Chart created.
    key_artifacts_present = result.get('notebook_modified', False) and (result.get('csv_modified', False) or result.get('chart_modified', False))
    passed = (score >= 60) and key_artifacts_present

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }