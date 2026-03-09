#!/usr/bin/env python3
import json
import os
import tempfile
import math

def verify_tou_cost_analysis(traj, env_info, task_info):
    """
    Verifier for Time-of-Use Cost Analysis.
    
    Checks:
    1. File existence and JSON validity (20pts)
    2. Schema compliance (required keys) (10pts)
    3. Feed identification (10pts)
    4. Tariff parameter usage (10pts)
    5. Mathematical consistency (20pts)
    6. Accuracy against ground truth (30pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    passed = False

    # Check 1: File Existence & Anti-gaming (20pts)
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Report file /home/ga/tou_report.json not found."}
    
    if not result.get("output_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Report file was not created/modified during the task session."}

    score += 20
    feedback.append("File exists and created during task.")

    # Parse Agent Report
    agent_report = result.get("agent_report", {})
    if not agent_report:
         return {"passed": False, "score": score, "feedback": "Report file is empty or invalid JSON."}

    # Check 2: Schema Compliance (10pts)
    required_keys = [
        "feed_name", "feed_id", "peak_kwh", "offpeak_kwh", "total_kwh",
        "peak_cost_usd", "offpeak_cost_usd", "total_cost_usd", "tou_savings_usd"
    ]
    missing = [k for k in required_keys if k not in agent_report]
    if not missing:
        score += 10
        feedback.append("JSON structure is valid.")
    else:
        feedback.append(f"Missing JSON keys: {missing}")

    # Check 3: Feed ID (10pts)
    gt = result.get("ground_truth", {})
    expected_feed_id = gt.get("ground_truth_feed_id")
    
    if agent_report.get("feed_id") == expected_feed_id:
        score += 10
        feedback.append("Correct feed identified.")
    else:
        feedback.append(f"Wrong feed ID. Expected {expected_feed_id}, got {agent_report.get('feed_id')}.")

    # Check 4: Tariff Parameters (10pts)
    # Check if they hardcoded the rates correctly in the JSON
    if (agent_report.get("peak_rate_usd") == 0.28 and 
        agent_report.get("offpeak_rate_usd") == 0.12):
        score += 10
        feedback.append("Tariff rates correct.")
    else:
        feedback.append("Incorrect tariff rates reported.")

    # Check 5: Internal Math Consistency (20pts)
    # total_kwh ~= peak + offpeak
    try:
        pk = agent_report.get("peak_kwh", 0)
        opk = agent_report.get("offpeak_kwh", 0)
        tot = agent_report.get("total_kwh", 0)
        
        pc = agent_report.get("peak_cost_usd", 0)
        opc = agent_report.get("offpeak_cost_usd", 0)
        tot_c = agent_report.get("total_cost_usd", 0)
        
        math_score = 0
        if abs(pk + opk - tot) < 0.1: math_score += 10
        if abs(pc + opc - tot_c) < 0.1: math_score += 10
        
        score += math_score
        if math_score == 20:
            feedback.append("Internal calculations consistent.")
        else:
            feedback.append("Internal calculations inconsistent (Total != Sum of parts).")
    except:
        feedback.append("Error verifying math (types mismatch).")

    # Check 6: Accuracy vs Ground Truth (30pts)
    # We check Total kWh and Total Cost
    gt_kwh = gt.get("ground_truth_total_kwh", 0)
    gt_cost = gt.get("ground_truth_total_cost", 0)
    
    # Allow 5% tolerance (different integration methods: trapezoid vs rectangle vs sampling)
    accuracy_score = 0
    
    if gt_kwh > 0:
        # Check Energy Accuracy
        diff_kwh = abs(tot - gt_kwh)
        pct_diff_kwh = (diff_kwh / gt_kwh) * 100
        if pct_diff_kwh < 5.0:
            accuracy_score += 15
            feedback.append(f"Energy calculation accurate ({pct_diff_kwh:.1f}% error).")
        else:
            feedback.append(f"Energy calculation inaccurate. Agent: {tot}, GT: {gt_kwh} ({pct_diff_kwh:.1f}% error).")
            
        # Check Cost Accuracy
        diff_cost = abs(tot_c - gt_cost)
        pct_diff_cost = (diff_cost / gt_cost) * 100
        if pct_diff_cost < 5.0:
            accuracy_score += 15
            feedback.append(f"Cost calculation accurate ({pct_diff_cost:.1f}% error).")
        else:
             feedback.append(f"Cost calculation inaccurate. Agent: {tot_c}, GT: {gt_cost} ({pct_diff_cost:.1f}% error).")
    else:
        feedback.append("Ground truth generation failed, skipping accuracy check.")
        # If GT failed, give points if math was consistent to be fair
        accuracy_score = 30 
    
    score += accuracy_score

    # Final result
    if score >= 60:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }