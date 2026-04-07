#!/usr/bin/env python3
import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pal_analysis(traj, env_info, task_info):
    """
    Verifier for Paired Associate Learning (PAL) Analysis task.
    Programmatic checks evaluating JSON validity, exclusion logic, and accurately computed scores 
    dynamically derived from the generated dataset.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    score = 0
    feedback_parts = []
    
    # Check export meta to ensure the file was made by the agent
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                meta = json.load(f)
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to get export result: {e}"}
        
    if not meta.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/pebl/analysis/pal_report.json not found."}
    if not meta.get('file_created_during_task'):
        logger.warning("File might not have been created during task time window.")

    # 1. Valid JSON Output (10 pts)
    report = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            copy_from_env('/home/ga/pebl/analysis/pal_report.json', tmp.name)
            with open(tmp.name, 'r') as f:
                report = json.load(f)
            os.unlink(tmp.name)
        score += 10
        feedback_parts.append("[+10] Output is valid JSON")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Output file is not valid JSON: {e}"}

    # Fetch CSV to compute precise Ground Truth dynamically
    csv_rows = []
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp:
            copy_from_env('/home/ga/pebl/data/pal_raw_data.csv', tmp.name)
            with open(tmp.name, 'r') as f:
                reader = csv.DictReader(f)
                csv_rows = list(reader)
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read CSV for ground truth: {e}"}

    # Compute Ground Truth from raw CSV
    ppt_rt = {}
    for r in csv_rows:
        pid = r['participant_id']
        ppt_rt.setdefault(pid, []).append(float(r['mean_rt_ms']))
        
    # ID dummies (mean RT < 200)
    dummy_pids = set(pid for pid, rts in ppt_rt.items() if sum(rts)/len(rts) < 200)
    
    gt_data = {}
    for r in csv_rows:
        pid = r['participant_id']
        if pid in dummy_pids:
            continue
            
        if pid not in gt_data:
            gt_data[pid] = {'max_stage': 0, 'first_attempt_score': 0, 'total_errors': 0}
            
        stage = int(r['stage'])
        attempt = int(r['attempt'])
        passed = int(r['passed'])
        p_correct = int(r['patterns_correct'])
        errors = int(r['errors'])
        
        # Max stage
        if passed == 1 and stage > gt_data[pid]['max_stage']:
            gt_data[pid]['max_stage'] = stage
            
        # First attempt score
        if attempt == 1:
            gt_data[pid]['first_attempt_score'] += p_correct
            
        # Total errors
        gt_data[pid]['total_errors'] += errors

    if not gt_data:
        return {"passed": False, "score": 0, "feedback": "Could not compute ground truth (empty data?)."}

    group_max_stage = sum(v['max_stage'] for v in gt_data.values()) / len(gt_data)
    group_first_attempt = sum(v['first_attempt_score'] for v in gt_data.values()) / len(gt_data)
    group_errors = sum(v['total_errors'] for v in gt_data.values()) / len(gt_data)

    # 2. Dummy Participant Excluded (20 pts)
    agent_participants = report.get('participants', [])
    if not isinstance(agent_participants, list):
        return {"passed": False, "score": score, "feedback": "'participants' key missing or not a list."}

    agent_pt_map = {}
    for p in agent_participants:
        pid = p.get('id') or p.get('participant_id')
        if pid:
            agent_pt_map[pid] = p

    dummy_excluded = False
    for dummy_pid in dummy_pids:
        # Check if missing entirely (acceptable) or explicitly excluded via boolean
        if dummy_pid not in agent_pt_map:
            dummy_excluded = True
        else:
            if agent_pt_map[dummy_pid].get('excluded') in (True, 'true', 1, 'yes'):
                dummy_excluded = True

    if dummy_excluded:
        score += 20
        feedback_parts.append("[+20] Dummy participant correctly excluded")
    else:
        feedback_parts.append("[0] Dummy participant NOT properly excluded")

    # 3-5. Correct Clinical Metrics (20 pts each)
    max_stage_match = 0
    first_attempt_match = 0
    total_errors_match = 0
    
    valid_count = len(gt_data)
    
    for pid, gt in gt_data.items():
        agent_pt = agent_pt_map.get(pid)
        if not agent_pt or agent_pt.get('excluded'):
            continue
            
        a_max = agent_pt.get('max_stage_completed')
        if a_max is not None and int(a_max) == gt['max_stage']:
            max_stage_match += 1
            
        a_fa = agent_pt.get('first_attempt_memory_score')
        if a_fa is not None and int(a_fa) == gt['first_attempt_score']:
            first_attempt_match += 1
            
        a_err = agent_pt.get('total_errors')
        if a_err is not None and int(a_err) == gt['total_errors']:
            total_errors_match += 1

    if valid_count > 0:
        if max_stage_match / valid_count >= 0.9:
            score += 20
            feedback_parts.append("[+20] Max Stage accurate")
        else:
            feedback_parts.append(f"[0] Max Stage match rate too low ({max_stage_match}/{valid_count})")
            
        if first_attempt_match / valid_count >= 0.9:
            score += 20
            feedback_parts.append("[+20] First Attempt Score accurate")
        else:
            feedback_parts.append(f"[0] First Attempt match rate too low ({first_attempt_match}/{valid_count})")
            
        if total_errors_match / valid_count >= 0.9:
            score += 20
            feedback_parts.append("[+20] Total Errors accurate")
        else:
            feedback_parts.append(f"[0] Total Errors match rate too low ({total_errors_match}/{valid_count})")

    # 6. Group Means Correct (10 pts)
    group_means = report.get('group_means', {})
    gm_score = 0
    if group_means:
        g_max = group_means.get('max_stage_completed')
        g_fa = group_means.get('first_attempt_memory_score')
        g_err = group_means.get('total_errors')
        
        c = 0
        if g_max is not None and abs(float(g_max) - group_max_stage) <= 0.05:
            c += 1
        if g_fa is not None and abs(float(g_fa) - group_first_attempt) <= 0.05:
            c += 1
        if g_err is not None and abs(float(g_err) - group_errors) <= 0.05:
            c += 1
            
        if c == 3:
            gm_score = 10
            feedback_parts.append("[+10] Group means accurate")
        elif c > 0:
            gm_score = c * 3
            feedback_parts.append(f"[+{gm_score}] Group means partially accurate")
        else:
            feedback_parts.append("[0] Group means inaccurate")
    else:
        feedback_parts.append("[0] Group means missing")
        
    score += gm_score
    
    # Cap score
    score = min(100, int(score))
    
    # Needs to hit a key metric requirement plus threshold
    key_metrics_passed = (max_stage_match/valid_count >= 0.9 or 
                          first_attempt_match/valid_count >= 0.9 or 
                          total_errors_match/valid_count >= 0.9)
    
    passed = score >= 70 and dummy_excluded and key_metrics_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }