#!/usr/bin/env python3
"""
Verifier for configure_regression_channel_analysis task.

Goal: Configure SPY chart with:
1. Regression Channel (Period=50, Width=2)
2. R-Squared (Period=50)
3. Stochastics (K=14, D=3, Smooth=3)

Scoring (100 points max):
- Workspace Modified: 15 pts
- SPY Chart Found: 20 pts (Gatekeeper: 0 total if missing)
- Regression Channel: 20 pts (10 presence + 10 params)
- R-Squared: 20 pts (10 presence + 10 params)
- Stochastics: 15 pts (5 presence + 10 params)
- Parameter Tolerances: Exact match required for integers, small delta for float (Width).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\configure_regression_channel_analysis_result.json"

def verify_configure_regression_channel_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env(RESULT_PATH, temp_path)
            with open(temp_path, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result file: {e}"}

    score = 0
    feedback_parts = []
    
    # Check 1: Workspace Modification (15 pts)
    if result.get('workspace_modified', False):
        score += 15
        feedback_parts.append("Workspace saved (+15)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")
        
    # Check 2: SPY Found (20 pts) - GATEKEEPER
    if result.get('spy_found', False):
        score += 20
        feedback_parts.append("SPY chart found (+20)")
    else:
        feedback_parts.append("SPY chart NOT found")
        # If SPY is missing, likely no relevant work was done. Cap score here.
        return {
            "passed": False,
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " (SPY chart required to proceed)"
        }

    indicators = result.get('indicators', {})

    # Check 3: Regression Channel (20 pts)
    reg = indicators.get('RegressionChannel', {})
    if reg.get('found', False):
        score += 10
        # Check params
        p_score = 0
        if reg.get('period') == 50: p_score += 5
        # Width might be float 2.0 or int 2
        try:
            if abs(float(reg.get('width', 0)) - 2.0) < 0.1: p_score += 5
        except: pass
        
        score += p_score
        feedback_parts.append(f"RegChannel found (+10), Params +{p_score}")
    else:
        feedback_parts.append("RegChannel missing (0)")

    # Check 4: R-Squared (20 pts)
    rsq = indicators.get('RSquared', {})
    if rsq.get('found', False):
        score += 10
        if rsq.get('period') == 50:
            score += 10
            feedback_parts.append("R-Squared correct (+20)")
        else:
            feedback_parts.append("R-Squared found but wrong params (+10)")
    else:
        feedback_parts.append("R-Squared missing (0)")

    # Check 5: Stochastics (15 pts)
    stoch = indicators.get('Stochastics', {})
    if stoch.get('found', False):
        score += 5
        p_score = 0
        if stoch.get('period_k') == 14: p_score += 3
        if stoch.get('period_d') == 3: p_score += 3
        if stoch.get('smooth') == 3: p_score += 4
        
        score += p_score
        feedback_parts.append(f"Stochastics found (+5), Params +{p_score}")
    else:
        feedback_parts.append("Stochastics missing (0)")
        
    # Final Tally
    # Max possible: 15 + 20 + 20 + 20 + 15 = 90? 
    # Let's adjust scoring to sum to 100.
    # Workspace(15) + SPY(20) + Reg(20) + Rsq(20) + Stoch(25) = 100
    # Current Stoch is 15. Total is 90.
    # Let's add 10 points bonus if all indicators are present.
    
    all_present = (reg.get('found') and rsq.get('found') and stoch.get('found'))
    if all_present:
        score += 10
        feedback_parts.append("All indicators present bonus (+10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }