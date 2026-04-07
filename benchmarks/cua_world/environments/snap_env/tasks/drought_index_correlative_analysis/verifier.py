#!/usr/bin/env python3
"""
Verifier for drought_index_correlative_analysis task.

Scoring breakdown (must sum to exactly 100):
  1. DIMAP product saved:                        15 pts
  2. NDVI band correctly computed:               25 pts
  3. Plot image exported:                        20 pts
  4. Statistics file exported:                   20 pts
  5. Stats contain correct metrics/keywords:     20 pts
                                          TOTAL: 100 pts
Pass threshold: 70
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_drought_index_correlative_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    result_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env('/tmp/drought_index_result.json', result_path)
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    score = 0
    feedback = []

    # Criterion 1: DIMAP product saved (15 pts)
    if result.get('dim_found') and result.get('dim_created_after_start'):
        score += 15
        feedback.append("DIMAP product successfully saved during task (+15)")
    elif result.get('dim_found'):
        score += 7
        feedback.append("DIMAP product found but timestamp unclear (+7)")
    else:
        feedback.append("No saved DIMAP product found (0/15)")

    # Criterion 2: NDVI band correctly computed (25 pts)
    if result.get('ndvi_band_found'):
        expr = result.get('ndvi_expression', '').lower().replace(' ', '')
        has_b2 = 'band_2' in expr or 'band2' in expr
        has_b3 = 'band_3' in expr or 'band3' in expr
        has_ops = '-' in expr and '/' in expr and '+' in expr
        
        if has_b2 and has_b3 and has_ops:
            score += 25
            feedback.append("NDVI band found with correct mathematical expression (+25)")
        elif has_b2 and has_b3:
            score += 15
            feedback.append("NDVI band found but formula structure is imperfect (+15)")
        else:
            score += 10
            feedback.append("NDVI band found but incorrect expression used (+10)")
    else:
        feedback.append("NDVI band not found in DIMAP product (0/25)")

    # Criterion 3: Plot image exported (20 pts)
    if result.get('plot_found') and result.get('plot_created_after_start'):
        plot_size = result.get('plot_size_bytes', 0)
        if plot_size > 5000:
            score += 20
            feedback.append("Valid Correlative Plot image exported (+20)")
        else:
            score += 10
            feedback.append("Exported plot image is unusually small (+10)")
    else:
        feedback.append("Correlative Plot image not exported (0/20)")

    # Criterion 4: Statistics file exported (20 pts)
    if result.get('stats_found') and result.get('stats_created_after_start'):
        score += 20
        feedback.append("Statistical data file exported successfully (+20)")
    else:
        feedback.append("Statistical data file not exported (0/20)")

    # Criterion 5: Stats contain correct metrics (20 pts)
    stats_content = result.get('stats_content', '').lower()
    if stats_content:
        # Looking for evidence that it represents the Correlative Plot output 
        # (needs regression info + correct variables)
        has_regression = any(kw in stats_content for kw in ['regression', 'correlation', 'r^2', 'equation', 'intercept'])
        has_vars = 'ndvi' in stats_content or 'band_1' in stats_content or 'swir' in stats_content
        
        if has_regression and has_vars:
            score += 20
            feedback.append("Stats file contains relevant regression data and variables (+20)")
        elif has_regression or has_vars:
            score += 10
            feedback.append("Stats file contains partial expected data (+10)")
        else:
            feedback.append("Stats file does not contain recognized regression metrics (0/20)")
    else:
        feedback.append("No stats content to verify (0/20)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }