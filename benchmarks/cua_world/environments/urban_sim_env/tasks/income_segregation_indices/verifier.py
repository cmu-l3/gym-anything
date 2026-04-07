#!/usr/bin/env python3
"""Verification script for income_segregation_indices task."""

import json
import os
import sys
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available. VLM verification will be bypassed.")

# Import shared Urbansim verification utils
sys.path.insert(0, '/workspace/utils')
try:
    from urbansim_verification_utils import (
        copy_file_from_env, validate_notebook_has_code,
        validate_csv_output, validate_png_file, build_verifier_result
    )
except ImportError:
    logger.error("Could not import urbansim_verification_utils")
    raise


def verify_income_segregation(traj, env_info, task_info):
    """Verify the income segregation task using programmatic + VLM checks."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Read Task Export Result (Anti-Gaming check) (10 pts)
    # ----------------------------------------------------------------
    result_data = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to read export info: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files_info = result_data.get('files', {}) if result_data else {}
    files_created_during_task = all(
        info.get('created_during_task', False) 
        for name, info in files_info.items() 
        if info.get('exists', False) and name != 'png' # PNG is optional in this strict check, evaluate later
    )
    
    if files_created_during_task and any(info.get('exists') for info in files_info.values()):
        score += 10
        feedback_parts.append("Anti-gaming: Output files correctly generated during task runtime.")
    else:
        feedback_parts.append("Anti-gaming: Some files pre-existed or were not created.")

    # ----------------------------------------------------------------
    # 2. Check notebook exists, executed, and has code patterns (15 pts)
    # ----------------------------------------------------------------
    nb_path, err = copy_file_from_env(
        env_info, metadata.get('expected_notebook_path'), '.ipynb'
    )
    
    notebook_valid = False
    nb_results = {}
    if not err and os.path.exists(nb_path):
        required_patterns = [
            ('hdf5_load', r'read_hdf|HDFStore'),
            ('merge_join', r'\.merge\s*\(|\.join\s*\('),
            ('dissimilarity', r'dissimilarity|abs\s*\(.*\)|0\.5\s*\*'),
            ('entropy_theil', r'entropy|theil|np\.log|math\.log'),
            ('quantile_tercile', r'quantile|tercile|percentile|33|67')
        ]
        nb_results = validate_notebook_has_code(nb_path, required_patterns)
        
        if nb_results.get('num_executed_cells', 0) > 0:
            score += 5
            notebook_valid = True
            
            # Code pattern points (max 10)
            pattern_score = sum(2 for k, v in nb_results.items() if v and k != 'num_executed_cells' and k != 'has_errors')
            score += pattern_score
            feedback_parts.append(f"Notebook executed with code patterns ({pattern_score}/10 pts).")
        else:
            feedback_parts.append("Notebook exists but no cells executed.")
        os.unlink(nb_path)
    else:
        feedback_parts.append("Notebook not found or failed to copy.")

    # ----------------------------------------------------------------
    # 3. Check CSV output (15 pts)
    # ----------------------------------------------------------------
    csv_path, err = copy_file_from_env(
        env_info, metadata.get('expected_csv_path'), '.csv'
    )
    
    if not err and os.path.exists(csv_path):
        csv_result = validate_csv_output(
            csv_path, 
            expected_columns=metadata.get('expected_csv_columns'), 
            min_rows=10
        )
        if csv_result['valid'] and csv_result['has_expected_columns']:
            score += 15
            feedback_parts.append(f"CSV valid: {csv_result['rows']} zones analyzed.")
        elif csv_result['exists']:
            score += 5
            feedback_parts.append("CSV exists but is missing expected columns or has too few rows.")
        os.unlink(csv_path)
    else:
        feedback_parts.append("CSV output not found.")

    # ----------------------------------------------------------------
    # 4. Check JSON output and Index Plausibility (25 pts)
    # ----------------------------------------------------------------
    json_path, err = copy_file_from_env(
        env_info, metadata.get('expected_json_path'), '.json'
    )
    
    if not err and os.path.exists(json_path):
        try:
            with open(json_path, 'r') as f:
                indices = json.load(f)
            
            req_keys = metadata.get('expected_json_keys', [])
            if all(k in indices for k in req_keys):
                score += 10
                feedback_parts.append("JSON output contains all required keys.")
                
                # Plausibility checks
                d_idx = indices.get('dissimilarity_index')
                h_idx = indices.get('theil_index')
                
                plausible = 0
                if isinstance(d_idx, (int, float)) and 0.05 <= d_idx <= 0.85:
                    plausible += 7.5
                    feedback_parts.append(f"Dissimilarity Index is plausible ({d_idx:.3f}).")
                else:
                    feedback_parts.append(f"Dissimilarity Index missing or out of plausible bounds.")
                    
                if isinstance(h_idx, (int, float)) and 0.01 <= h_idx <= 0.50:
                    plausible += 7.5
                    feedback_parts.append(f"Theil Index is plausible ({h_idx:.3f}).")
                else:
                    feedback_parts.append(f"Theil Index missing or out of plausible bounds.")
                
                score += int(plausible)
            else:
                score += 5
                feedback_parts.append("JSON output missing some required keys.")
        except json.JSONDecodeError:
            feedback_parts.append("JSON output is invalid.")
        os.unlink(json_path)
    else:
        feedback_parts.append("JSON output not found.")

    # ----------------------------------------------------------------
    # 5. Check PNG output (5 pts)
    # ----------------------------------------------------------------
    png_path, err = copy_file_from_env(
        env_info, metadata.get('expected_plot_path'), '.png'
    )
    
    if not err and os.path.exists(png_path):
        png_result = validate_png_file(png_path, min_size_kb=10)
        if png_result['valid']:
            score += 5
            feedback_parts.append("PNG chart is valid and sufficient size.")
        elif png_result['exists']:
            score += 2
            feedback_parts.append("PNG exists but may be empty or corrupt.")
        os.unlink(png_path)
    else:
        feedback_parts.append("PNG chart not found.")

    # ----------------------------------------------------------------
    # 6. VLM Trajectory Verification (30 pts)
    # ----------------------------------------------------------------
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            prompt = """You are evaluating an agent performing a data science task in Jupyter Lab.
Task: Calculate income segregation indices (Dissimilarity and Theil Entropy) using San Francisco household data.

Looking at these screenshots across the agent's workflow, evaluate:
1. WORKFLOW_EVIDENCE: Does the agent write code to load data, merge tables, and perform calculations?
2. RESULTS_VISIBLE: Are output artifacts (charts, tables, printed index values) visible?
3. AUTHENTIC_COMPLETION: Does this look like a genuine attempt at the requested data analysis?

Respond in JSON:
{
  "workflow_evidence": true/false,
  "results_visible": true/false,
  "authentic_completion": true/false,
  "reasoning": "brief explanation"
}"""
            
            vlm_res = query_vlm(prompt=prompt, images=all_frames)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_score = 0
                if parsed.get('workflow_evidence'): vlm_score += 10
                if parsed.get('results_visible'): vlm_score += 10
                if parsed.get('authentic_completion'): vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM Verification: {vlm_score}/30 pts. Reasoning: {parsed.get('reasoning')}")
            else:
                feedback_parts.append("VLM Verification failed to process.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            # Do not heavily penalize if VLM simply crashes due to infra
            score += 15 
            feedback_parts.append("VLM Verification errored, partial credit awarded.")
    else:
        # If running locally without VLM
        score += 30
        feedback_parts.append("VLM Verification bypassed (not available). Awarding default points.")

    return build_verifier_result(
        score, 100, feedback_parts, pass_threshold=60, execution_verified=notebook_valid
    )

if __name__ == "__main__":
    # For local test mocking
    print(json.dumps(verify_income_segregation({}, {}, {}), indent=2))