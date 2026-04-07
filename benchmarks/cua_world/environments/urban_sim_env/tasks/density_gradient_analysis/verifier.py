#!/usr/bin/env python3
"""Verifier for density_gradient_analysis task."""

import json
import os
import math
import logging
import sys

# Ensure urbansim_verification_utils is accessible
sys.path.append("/workspace/utils")
try:
    from urbansim_verification_utils import (
        copy_result_json, copy_file_from_env, validate_notebook_has_code,
        validate_csv_output, validate_png_file, build_verifier_result
    )
except ImportError:
    logging.warning("Could not import urbansim_verification_utils")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_density_gradient(traj, env_info, task_info):
    """Verify residential density gradient analysis."""
    metadata = task_info.get('metadata', {})
    expected_nb_path = metadata.get('expected_notebook_path')
    expected_csv_path = metadata.get('expected_csv_path')
    expected_json_path = metadata.get('expected_json_path')
    expected_plot_path = metadata.get('expected_plot_path')
    expected_csv_cols = metadata.get('expected_csv_columns', [])
    expected_json_keys = metadata.get('expected_json_keys', [])

    score = 0
    feedback = []

    # 1. Check top-level result JSON
    result_meta, err = copy_result_json(env_info)
    if err or not result_meta:
        return {"passed": False, "score": 0, "feedback": f"Failed to get export result: {err}"}

    # 2. Validate CSV File (20 pts)
    csv_score = 0
    local_csv, err = copy_file_from_env(env_info, expected_csv_path, '.csv')
    if local_csv and not err:
        csv_info = validate_csv_output(local_csv, expected_columns=expected_csv_cols, min_rows=10)
        if csv_info['exists']:
            csv_score += 5
            if csv_info['has_expected_columns']:
                csv_score += 10
            elif len(set(csv_info['columns']).intersection(set(expected_csv_cols))) >= 3:
                csv_score += 5  # Partial columns
            if csv_info['valid'] and csv_info['rows'] >= 10:
                csv_score += 5
        os.unlink(local_csv)
    score += csv_score
    feedback.append(f"CSV: {csv_score}/20")

    # 3. Validate JSON Summary File (25 pts)
    json_score = 0
    local_json, err = copy_file_from_env(env_info, expected_json_path, '.json')
    if local_json and not err:
        try:
            with open(local_json, 'r') as f:
                summary = json.load(f)
            json_score += 5  # JSON exists and valid

            keys_present = [k for k in expected_json_keys if k in summary]
            if len(keys_present) == len(expected_json_keys):
                json_score += 5
            elif len(keys_present) >= 3:
                json_score += 2

            # Mathematical validation
            slope = summary.get('slope')
            r2 = summary.get('r_squared')
            num_zones = summary.get('num_zones')

            if isinstance(slope, (int, float)) and slope < 0:
                json_score += 10  # Density decays exponentially with distance
            
            if isinstance(r2, (int, float)) and 0 <= r2 <= 1:
                json_score += 5
            
        except Exception as e:
            feedback.append(f"JSON Parse Error: {e}")
        finally:
            os.unlink(local_json)
    score += json_score
    feedback.append(f"JSON: {json_score}/25")

    # 4. Validate PNG Plot (15 pts)
    png_score = 0
    local_png, err = copy_file_from_env(env_info, expected_plot_path, '.png')
    if local_png and not err:
        png_info = validate_png_file(local_png, min_size_kb=10)
        if png_info['exists']:
            png_score += 5
            if png_info['valid']:
                png_score += 10
        os.unlink(local_png)
    score += png_score
    feedback.append(f"Plot: {png_score}/15")

    # 5. Validate Notebook Code Execution (40 pts)
    nb_score = 0
    execution_verified = False
    local_nb, err = copy_file_from_env(env_info, expected_nb_path, '.ipynb')
    if local_nb and not err:
        patterns = [
            ('data_load', r'read_hdf|HDFStore'),
            ('grouping', r'groupby|sum|agg'),
            ('distance', r'distance|euclidean|sqrt|pow|\*\* 2'),
            ('regression', r'OLS|LinearRegression|linregress|polyfit|lstsq'),
            ('log_transform', r'log|ln'),
            ('outliers', r'std|residual|outlier|deviation')
        ]
        
        nb_info = validate_notebook_has_code(local_nb, patterns)
        
        if nb_info['data_load']: nb_score += 5
        if nb_info['grouping']: nb_score += 5
        if nb_info['distance']: nb_score += 5
        if nb_info['regression']: nb_score += 10
        if nb_info['log_transform']: nb_score += 5
        if nb_info['outliers']: nb_score += 5
        
        if nb_info['num_executed_cells'] >= 4 and not nb_info['has_errors']:
            nb_score += 5
            execution_verified = True
            
        os.unlink(local_nb)
    score += nb_score
    feedback.append(f"Notebook Code: {nb_score}/40")

    # Use standard build result
    return build_verifier_result(
        score=score,
        max_score=100,
        feedback_parts=feedback,
        pass_threshold=60,
        execution_verified=execution_verified
    )