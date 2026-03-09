#!/usr/bin/env python3
"""
Verifier for focus_quality_assessment task.
"""

import json
import os
import tempfile
import logging
import re
import csv
import math

# Attempt to import scipy for correlation; fallback to manual calculation if not present
try:
    from scipy import stats
    HAS_SCIPY = True
except ImportError:
    HAS_SCIPY = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_spearman_manual(x, y):
    """Calculate Spearman rank correlation manually if scipy is missing."""
    n = len(x)
    if n < 2: return 0.0
    
    def get_ranks(data):
        sorted_indices = sorted(range(len(data)), key=lambda k: data[k])
        ranks = [0] * len(data)
        for rank, idx in enumerate(sorted_indices):
            ranks[idx] = rank + 1
        # Handle ties (simplified: use average rank)
        # This is a basic implementation; for perfect ties handling scipy is better
        return ranks

    rank_x = get_ranks(x)
    rank_y = get_ranks(y)
    
    d_sq_sum = sum((rx - ry)**2 for rx, ry in zip(rank_x, rank_y))
    rho = 1 - (6 * d_sq_sum) / (n * (n**2 - 1))
    return rho

def verify_focus_quality(traj, env_info, task_info):
    """
    Verify the focus quality assessment task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 2. Check File Existence & Freshness (Anti-Gaming)
    csv_info = result.get("csv_file", {})
    summary_info = result.get("summary_file", {})
    img_info = result.get("image_file", {})
    
    if csv_info.get("exists") and csv_info.get("fresh"):
        score += 15
        feedback.append("CSV output created successfully.")
    else:
        feedback.append("CSV output missing or not created during task.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    if summary_info.get("exists") and summary_info.get("fresh"):
        score += 10
        feedback.append("Summary report created.")
    else:
        feedback.append("Summary report missing.")

    if img_info.get("exists") and img_info.get("fresh") and img_info.get("size", 0) > 5000:
        score += 10
        feedback.append("Visual comparison image created.")
    else:
        feedback.append("Visual comparison image missing or empty.")

    # 3. Analyze CSV Content
    # We need to pull the actual CSV file to verify the metrics
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_rows = []
    try:
        copy_from_env("/tmp/focus_metrics_export.csv", temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            csv_rows = list(reader)
    except Exception as e:
        feedback.append(f"Failed to read CSV content: {e}")
    finally:
        if os.path.exists(temp_csv.name): os.unlink(temp_csv.name)

    # Basic CSV Structure Check (15 pts)
    required_cols = ["filename", "laplacian_var", "normalized_var", "tenengrad", "stddev", "rank", "qc_status"]
    if len(csv_rows) >= 20:
        headers = csv_rows[0].keys()
        missing_cols = [c for c in required_cols if c not in headers and 
                        not any(h.lower() == c.lower() for h in headers)] # case-insensitive check
        
        if not missing_cols:
            score += 15
            feedback.append(f"CSV has valid structure ({len(csv_rows)} rows).")
        else:
            feedback.append(f"CSV missing columns: {missing_cols}")
    else:
        feedback.append(f"CSV has insufficient rows ({len(csv_rows)} < 20).")

    # 4. Metric Validity & Ground Truth Correlation (30 pts)
    # The BBBC005 filenames look like: SIMCEPImages_A01_C1_F1_s1_w1.TIF
    # F1 = Sharpest, F5 = Blurriest.
    # Metric (e.g. VoL) should correlate NEGATIVELY with F-number.
    
    vol_values = []
    f_numbers = []
    valid_metrics = True
    
    for row in csv_rows:
        try:
            # Flexible column naming
            vol = float(row.get('laplacian_var') or row.get('Laplacian_Var') or 0)
            fname = row.get('filename') or row.get('Filename') or ""
            
            # Extract F-number
            match = re.search(r'_F(\d)_', fname)
            if match and vol > 0:
                f_num = int(match.group(1))
                vol_values.append(vol)
                f_numbers.append(f_num)
            
            if vol <= 0: valid_metrics = False
        except:
            valid_metrics = False

    if valid_metrics and len(vol_values) > 10:
        score += 10
        feedback.append("Metric values are valid positive numbers.")
        
        # Calculate Correlation
        if HAS_SCIPY:
            rho, _ = stats.spearmanr(f_numbers, vol_values)
        else:
            rho = calculate_spearman_manual(f_numbers, vol_values)
            
        # We expect HIGH F-number (blur) -> LOW VoL (sharpness)
        # So correlation should be negative
        logger.info(f"Spearman Correlation (F-num vs VoL): {rho}")
        
        if rho <= -0.4:
            score += 20
            feedback.append(f"Strong correlation with ground truth verified (rho={rho:.2f}).")
        elif rho <= -0.2:
            score += 10
            feedback.append(f"Weak correlation with ground truth (rho={rho:.2f}).")
        else:
            feedback.append(f"Metrics do not correlate with focus level (rho={rho:.2f}). Check metric calculation.")
    else:
        feedback.append("Could not extract enough valid data points for correlation check.")

    # 5. Rank & Classification Consistency (20 pts)
    # Check if Rank 1 has higher VoL than Rank N
    ranks_correct = True
    class_correct = True
    
    # Sort rows by rank just in case
    try:
        sorted_rows = sorted(csv_rows, key=lambda x: int(x.get('rank', 999)))
        if len(sorted_rows) > 1:
            best_vol = float(sorted_rows[0].get('laplacian_var', 0))
            worst_vol = float(sorted_rows[-1].get('laplacian_var', 0))
            
            if best_vol <= worst_vol:
                ranks_correct = False
            
            # Check median split
            vols = [float(r.get('laplacian_var', 0)) for r in sorted_rows]
            vols.sort()
            median_vol = vols[len(vols)//2]
            
            pass_count = 0
            fail_count = 0
            
            for r in sorted_rows:
                v = float(r.get('laplacian_var', 0))
                status = r.get('qc_status', '').upper()
                if status == 'PASS':
                    pass_count += 1
                    if v < median_vol and abs(v - median_vol) > 0.1: # tolerance
                        class_correct = False
                elif status == 'FAIL':
                    fail_count += 1
            
            if pass_count == 0 or fail_count == 0:
                class_correct = False

        if ranks_correct:
            score += 10
            feedback.append("Ranking logic appears correct.")
        else:
            feedback.append("Ranking logic incorrect (Best VoL <= Worst VoL).")
            
        if class_correct:
            score += 10
            feedback.append("PASS/FAIL classification logic appears correct.")
        else:
            feedback.append("PASS/FAIL classification inconsistent with median.")

    except Exception as e:
        feedback.append(f"Error checking ranking logic: {e}")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }