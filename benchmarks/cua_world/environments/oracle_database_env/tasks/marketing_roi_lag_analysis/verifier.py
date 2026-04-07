#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_marketing_roi(traj, env_info, task_info):
    """
    Verifies the Marketing ROI Analysis task.
    Compares the agent's view results against ground truth calculated during setup.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # 1. Load Agent Result
    agent_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        try:
            copy_from_env('/tmp/task_result.json', tf.name)
            tf.seek(0)
            agent_result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load agent result: {e}"}

    # 2. Load Ground Truth (Hidden file)
    ground_truth = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf_gt:
        try:
            # Note: This requires the agent container to expose this path or use a shared volume
            # In this framework, we use copy_from_env to pull from container path defined in setup
            copy_from_env('/var/lib/oracle/roi_ground_truth.json', tf_gt.name)
            tf_gt.seek(0)
            ground_truth = json.load(tf_gt)
        except Exception as e:
            # Fallback/Debug: If ground truth missing, we can't score numerically
            return {"passed": False, "score": 0, "feedback": "Ground truth file missing in environment."}

    # 3. Scoring
    score = 0
    feedback = []
    
    # Check View Existence (10 pts)
    if not agent_result.get("view_exists"):
        return {"passed": False, "score": 0, "feedback": "View CAMPAIGN_ROI_ANALYSIS does not exist."}
    score += 10
    feedback.append("View created.")

    rows = agent_result.get("rows", [])
    if not rows:
        return {"passed": False, "score": 10, "feedback": "View created but returned no rows or query failed."}

    # Evaluate per Region (5 regions * 18 pts = 90 pts max distributed)
    # Actually, let's distribute by Metric Type across all regions
    
    # Tolerances
    CORR_TOL = 0.05
    SLOPE_TOL = 0.2
    
    regions_found = 0
    agg_score = 0
    corr_score = 0
    slope_score = 0
    strat_score = 0
    
    for row in rows:
        rid = str(int(row.get('region_id', 0)))
        if rid not in ground_truth:
            continue
            
        regions_found += 1
        gt = ground_truth[rid]
        
        # Check Aggregation (Total Spend/Sales) - 4 pts per region
        # Allow 1% error (rounding)
        if abs(row.get('total_spend', 0) - gt['total_spend']) / gt['total_spend'] < 0.01:
            agg_score += 2
        if abs(row.get('total_sales', 0) - gt['total_sales']) / gt['total_sales'] < 0.01:
            agg_score += 2
            
        # Check Correlations (Lag0 & Lag1) - 4 pts per region
        c0_ok = abs(row.get('corr_lag0', -99) - gt['corr0']) < CORR_TOL
        c1_ok = abs(row.get('corr_lag1', -99) - gt['corr1']) < CORR_TOL
        if c0_ok: corr_score += 2
        if c1_ok: corr_score += 2
        
        # Check Slopes - 4 pts per region
        s0_ok = abs(row.get('slope_lag0', -99) - gt['slope0']) < SLOPE_TOL
        s1_ok = abs(row.get('slope_lag1', -99) - gt['slope1']) < SLOPE_TOL
        if s0_ok: slope_score += 2
        if s1_ok: slope_score += 2
        
        # Check Strategy Text - 3 pts per region
        # Allow case-insensitive match
        agent_strat = str(row.get('best_strategy', '')).upper()
        if agent_strat == gt['strategy']:
            strat_score += 3
        else:
            feedback.append(f"Region {rid}: Expected {gt['strategy']}, got {agent_strat}")

    score += agg_score + corr_score + slope_score + strat_score
    
    # Detailed Feedback
    feedback.append(f"Aggregation Score: {agg_score}/20")
    feedback.append(f"Correlation Score: {corr_score}/20")
    feedback.append(f"Slope/ROI Score: {slope_score}/20")
    feedback.append(f"Strategy Class Score: {strat_score}/15")
    
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "aggregation": agg_score,
            "correlation": corr_score,
            "slope": slope_score,
            "strategy": strat_score
        }
    }