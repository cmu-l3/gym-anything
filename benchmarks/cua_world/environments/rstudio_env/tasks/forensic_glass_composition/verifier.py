#!/usr/bin/env python3
"""
Verifier for forensic_glass_composition task.

Verifies:
1. Package installation (CoDa specific)
2. Data transformation (CLR properties)
3. Data summarization (Geometric means)
4. Visualizations (Biplot and Ternary diagram)

Scores:
- Package Install: 10 pts
- Geometric Means CSV: 20 pts
- CLR Transformed CSV: 20 pts
- Biplot PNG: 25 pts
- Ternary PNG: 25 pts

Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forensic_glass(traj, env_info, task_info):
    """
    Verify forensic glass analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

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

    # 1. Package Installation (10 pts)
    if result.get('has_coda_package', False):
        score += 10
        feedback.append("CoDa package installed (10/10)")
    else:
        feedback.append("No specialized Compositional Analysis package found (0/10)")

    # 2. Geometric Means CSV (20 pts)
    geo = result.get('geometric_means', {})
    if geo.get('exists') and geo.get('is_new'):
        # Expecting around 7 rows (header + 6 types)
        rows = geo.get('row_count', 0)
        if rows >= 6:
            score += 20
            feedback.append(f"Geometric Means CSV valid ({rows} rows) (20/20)")
        elif rows > 1:
            score += 10
            feedback.append(f"Geometric Means CSV exists but row count suspicious ({rows}) (10/20)")
        else:
            score += 5
            feedback.append("Geometric Means CSV empty or invalid (5/20)")
    else:
        feedback.append("Geometric Means CSV missing or old (0/20)")

    # 3. CLR Transformed CSV (20 pts)
    clr = result.get('clr_transformed', {})
    if clr.get('exists') and clr.get('is_new'):
        if clr.get('is_valid_clr', False):
            score += 20
            feedback.append("CLR transformation verified (row sums ~0, negative values present) (20/20)")
        else:
            score += 10
            feedback.append("CLR CSV exists but values don't look like valid CLR (10/20)")
    else:
        feedback.append("CLR transformed CSV missing (0/20)")

    # 4. Biplot PNG (25 pts)
    biplot = result.get('biplot', {})
    if biplot.get('exists') and biplot.get('is_new'):
        size = biplot.get('size', 0)
        if size > 20480: # > 20KB
            score += 25
            feedback.append("Biplot PNG created (25/25)")
        else:
            score += 10
            feedback.append(f"Biplot PNG exists but suspiciously small ({size} bytes) (10/25)")
    else:
        feedback.append("Biplot PNG missing (0/25)")

    # 5. Ternary PNG (25 pts)
    ternary = result.get('ternary', {})
    if ternary.get('exists') and ternary.get('is_new'):
        size = ternary.get('size', 0)
        if size > 20480: # > 20KB
            score += 25
            feedback.append("Ternary PNG created (25/25)")
        else:
            score += 10
            feedback.append(f"Ternary PNG exists but suspiciously small ({size} bytes) (10/25)")
    else:
        feedback.append("Ternary PNG missing (0/25)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }