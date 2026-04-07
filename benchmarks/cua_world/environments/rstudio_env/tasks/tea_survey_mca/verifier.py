#!/usr/bin/env python3
"""
Verifier for tea_survey_mca task.

Scoring Breakdown (100 points):
1. Environment Setup (10 pts): FactoMineR installed.
2. Eigenvalues (20 pts): CSV exists, is new, and Dim 1/2 values match ground truth (approx 0.254, 0.228).
3. Coordinates (20 pts): CSV exists, is new, and has data.
4. Biplot (20 pts): PNG exists, is new, and reasonable size (>15KB).
5. Interpretation (15 pts): Summary text correctly identifies "Tea shop" (or similar) as high contributor.
6. Script Quality (15 pts): Analysis script created/modified.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tea_survey_mca(traj, env_info, task_info):
    """Verify Tea Survey MCA task results."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata targets
    expected_dim1 = 0.254
    expected_dim2 = 0.228
    tolerance = 0.01

    # 1. Environment Setup (10 pts)
    if result.get('pkg_installed', False):
        score += 10
        feedback.append("FactoMineR installed (10/10)")
    else:
        feedback.append("FactoMineR package not installed (0/10)")

    # 2. Eigenvalues Verification (20 pts)
    eigen_passed = False
    if result.get('eigen_exists') and result.get('eigen_is_new'):
        r_vals = result.get('r_extracted_values', {})
        val1 = r_vals.get('dim1_eigen')
        val2 = r_vals.get('dim2_eigen')
        
        # Check values if extracted successfully
        if val1 is not None and val2 is not None:
            try:
                v1 = float(val1)
                v2 = float(val2)
                # Check within tolerance
                if abs(v1 - expected_dim1) < tolerance and abs(v2 - expected_dim2) < tolerance:
                    score += 20
                    eigen_passed = True
                    feedback.append(f"Eigenvalues correct: Dim1={v1:.3f}, Dim2={v2:.3f} (20/20)")
                else:
                    feedback.append(f"Eigenvalues mismatch. Expected ~{expected_dim1}, ~{expected_dim2}. Got {v1}, {v2} (5/20)")
                    score += 5 # Partial credit for file existence
            except ValueError:
                feedback.append("Eigenvalues file format error (5/20)")
                score += 5
        else:
            feedback.append("Eigenvalues file exists but could not parse values (5/20)")
            score += 5
    else:
        feedback.append("Eigenvalues CSV missing or not created during task (0/20)")

    # 3. Coordinates Verification (20 pts)
    if result.get('coords_exists') and result.get('coords_is_new'):
        score += 20
        feedback.append("Coordinates CSV created (20/20)")
    else:
        feedback.append("Coordinates CSV missing (0/20)")

    # 4. Biplot Verification (20 pts)
    plot_exists = result.get('plot_exists')
    plot_size = int(result.get('plot_size_bytes', 0))
    if plot_exists and result.get('plot_is_new'):
        if plot_size > 15000: # >15KB implies content
            score += 20
            feedback.append(f"Biplot created and valid size ({plot_size} bytes) (20/20)")
        else:
            score += 10
            feedback.append(f"Biplot created but suspiciously small ({plot_size} bytes) (10/20)")
    else:
        feedback.append("Biplot PNG missing (0/20)")

    # 5. Interpretation (15 pts)
    summary_content = result.get('summary_content', '').lower()
    # "Tea shop" is the classic answer for highest contribution to Dim 1 in this specific dataset/subset
    # "Tea shop" or "Tea_shop" or "Tea.shop"
    if summary_content and ("tea" in summary_content and "shop" in summary_content):
        score += 15
        feedback.append(f"Correctly identified 'Tea shop' as high contributor (15/15)")
    elif summary_content:
        # Give partial credit if they put something else but followed instructions
        score += 5
        feedback.append(f"Summary provided but value '{summary_content}' may be incorrect (expected 'Tea shop') (5/15)")
    else:
        feedback.append("Summary text missing (0/15)")

    # 6. Process/Script Check (15 pts) - Implicitly checked via file creation "is_new" flags
    # We add explicit points here if the main outputs were created during the task
    if result.get('eigen_is_new') and result.get('plot_is_new'):
        score += 15
        feedback.append("Analysis workflow verified via new output files (15/15)")
    else:
        feedback.append("Analysis workflow incomplete (0/15)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }