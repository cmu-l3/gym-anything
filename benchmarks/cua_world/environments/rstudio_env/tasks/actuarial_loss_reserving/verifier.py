#!/usr/bin/env python3
"""
Verifier for actuarial_loss_reserving task.

Criteria:
1. ChainLadder package installed and used.
2. Mack Estimates CSV exists, has correct columns, and Total IBNR matches RAA ground truth (~54,089).
3. Risk Metrics CSV exists and contains a 99.5th percentile estimate (Solvency II VaR).
4. Development plot exists.
5. R script exists and shows evidence of using the correct functions.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth for RAA dataset
EXPECTED_MACK_IBNR = 54089
TOLERANCE_PERCENT = 0.05  # 5% tolerance on deterministic Mack result

# Bootstrap 99.5% VaR is stochastic but should be significantly higher than mean
# Mean is ~54k. 99.5% is usually 2.5-3x sigma above mean, or strictly > mean.
# With seed 123, it's a specific number, but allowing for range is safer against minor version diffs.
MIN_VAR_995 = 80000
MAX_VAR_995 = 300000

def verify_actuarial_reserving(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Package Installation (10 pts)
    if result.get('pkg_installed') == "TRUE":
        score += 10
        feedback.append("ChainLadder package installed (10/10)")
    else:
        feedback.append("ChainLadder package NOT installed (0/10)")

    # 2. Mack Estimates (30 pts)
    # 10 pts for file existence/creation
    if result.get('mack_exists') and result.get('mack_new'):
        score += 10
        
        # 10 pts for columns
        if result.get('mack_valid_cols'):
            score += 10
        else:
            feedback.append("Mack CSV missing required columns (0/10)")

        # 10 pts for accuracy
        try:
            total_ibnr = float(result.get('mack_total_ibnr', 0))
            diff = abs(total_ibnr - EXPECTED_MACK_IBNR)
            pct_diff = diff / EXPECTED_MACK_IBNR
            
            if pct_diff <= TOLERANCE_PERCENT:
                score += 10
                feedback.append(f"Mack IBNR accuracy good: {total_ibnr:.0f} (Target {EXPECTED_MACK_IBNR}) (10/10)")
            else:
                feedback.append(f"Mack IBNR inaccurate: {total_ibnr:.0f} (Target {EXPECTED_MACK_IBNR}, Diff {pct_diff:.1%}) (0/10)")
        except:
            feedback.append("Could not parse Mack IBNR (0/10)")
            
    else:
        feedback.append("Mack estimates file missing or not created during task (0/30)")

    # 3. Risk Metrics (30 pts)
    if result.get('risk_exists') and result.get('risk_new'):
        score += 10
        
        # 20 pts for valid VaR calculation
        try:
            var_995 = float(result.get('risk_995', 0))
            if MIN_VAR_995 <= var_995 <= MAX_VAR_995:
                score += 20
                feedback.append(f"99.5% VaR reasonable: {var_995:.0f} (20/20)")
            elif var_995 > 0:
                score += 10 # Partial credit for producing a number, even if way off
                feedback.append(f"99.5% VaR out of expected range: {var_995:.0f} (10/20)")
            else:
                feedback.append("99.5% VaR is zero or missing (0/20)")
        except:
            feedback.append("Could not parse VaR value (0/20)")
    else:
        feedback.append("Risk metrics file missing (0/30)")

    # 4. Plot (15 pts)
    if result.get('plot_exists') and result.get('plot_new'):
        size = result.get('plot_size', 0)
        if size > 10000: # 10KB minimum
            score += 15
            feedback.append("Development plot created (15/15)")
        else:
            score += 5
            feedback.append("Development plot too small/empty (5/15)")
    else:
        feedback.append("Development plot missing (0/15)")

    # 5. Script Quality (15 pts)
    if result.get('script_exists') and result.get('script_new'):
        if result.get('script_content_valid'):
            score += 15
            feedback.append("R script contains required function calls (15/15)")
        else:
            score += 5
            feedback.append("R script created but missing 'MackChainLadder' calls (5/15)")
    else:
        feedback.append("R script missing or not modified (0/15)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }