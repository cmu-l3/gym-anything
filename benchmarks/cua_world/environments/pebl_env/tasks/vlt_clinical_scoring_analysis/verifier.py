#!/usr/bin/env python3
"""
Verifier for vlt_clinical_scoring_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON                          (10 pts)
  2. Missing-age (sub-888) and Malingering (sub-999) excluded      (20 pts)
  3. Total acquisition correct (proves string cleaning)            (15 pts)
  4. Clinical indices math correct (slope, retro, retention)       (25 pts)
  5. Normative Z-scores mapped and calculated correctly            (20 pts)
  6. Group means exactly match ground truth across valid pool      (10 pts)

Pass threshold: 65 pts AND valid JSON AND total acquisition string cleaning successful.
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vlt_clinical_scoring_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Copy agent report
    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        agent_tmp = tmp.name
        
    try:
        copy_from_env('/home/ga/pebl/analysis/vlt_report.json', agent_tmp)
        with open(agent_tmp, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] Output file found and is valid JSON.')
    except FileNotFoundError:
        return {'passed': False, 'score': 0, 'feedback': 'Output file /home/ga/pebl/analysis/vlt_report.json not found.'}
    except Exception as e:
        return {'passed': False, 'score': 0, 'feedback': f'Output file is not valid JSON: {e}'}
    finally:
        if os.path.exists(agent_tmp):
            os.unlink(agent_tmp)
            
    # 2. Copy hidden ground truth
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        gt_tmp = tmp.name
        
    try:
        copy_from_env('/root/vlt_ground_truth.json', gt_tmp)
        with open(gt_tmp, encoding='utf-8') as f:
            gt = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': score, 'feedback': f'Error loading ground truth: {e}'}
    finally:
        if os.path.exists(gt_tmp):
            os.unlink(gt_tmp)

    # Build maps
    agent_parts = report.get("participants", [])
    agent_map = {}
    for p in agent_parts:
        pid = p.get("id") or p.get("participant_id")
        if pid:
            agent_map[str(pid)] = p

    gt_parts = gt.get("participants", [])
    gt_map = {str(p["id"]): p for p in gt_parts}

    # Criterion 2: Exclusions (sub-888, sub-999)
    exc_correct = 0
    for pid in ["sub-888", "sub-999"]:
        p_data = agent_map.get(pid)
        if p_data and p_data.get("excluded") in [True, "true", "True", 1, "yes"]:
            exc_correct += 1
        elif pid not in agent_map: # if completely omitted, consider excluded
            exc_correct += 1
            
    if exc_correct == 2:
        score += 20
        feedback_parts.append('[+20] Both missing-age and malingering participants correctly excluded.')
    elif exc_correct == 1:
        score += 10
        feedback_parts.append('[+10] One invalid participant excluded (partial credit).')
    else:
        feedback_parts.append('[0] Invalid participants not excluded.')

    # Mathematical criteria for valid subjects
    valid_ids = [k for k in gt_map.keys() if k not in ["sub-888", "sub-999"]]
    acq_correct = 0
    math_correct = 0
    z_correct = 0
    
    for pid in valid_ids:
        gt_p = gt_map[pid]
        ag_p = agent_map.get(pid, {})
        
        # Criterion 3: Total acquisition (proves string cleaning)
        acq = ag_p.get("total_acquisition")
        if acq is not None:
            try:
                if abs(float(acq) - float(gt_p["total_acquisition"])) < 0.1:
                    acq_correct += 1
            except (ValueError, TypeError):
                pass
            
        # Criterion 4: Clinical indices math
        slope = ag_p.get("learning_slope")
        retro = ag_p.get("retroactive_interference")
        dr = ag_p.get("delayed_retention")
        
        if slope is not None and retro is not None and dr is not None:
            try:
                if (abs(float(slope) - float(gt_p["learning_slope"])) < 0.1 and 
                    abs(float(retro) - float(gt_p["retroactive_interference"])) < 0.1 and 
                    abs(float(dr) - float(gt_p["delayed_retention"])) < 0.05):
                    math_correct += 1
            except (ValueError, TypeError):
                pass
                
        # Criterion 5: Z-scores
        z = ag_p.get("total_acquisition_zscore")
        if z is not None:
            try:
                if abs(float(z) - float(gt_p["total_acquisition_zscore"])) < 0.05:
                    z_correct += 1
            except (ValueError, TypeError):
                pass
            
    # Score distribution for maths
    if acq_correct >= len(valid_ids) - 2:
        score += 15
        feedback_parts.append('[+15] Total acquisition calculation correct (proves string cleaning).')
    elif acq_correct >= len(valid_ids) // 2:
        score += 7
        feedback_parts.append('[+7] Total acquisition correct for some participants (partial).')
    else:
        feedback_parts.append('[0] Total acquisition calculation incorrect (failed string cleaning?).')

    if math_correct >= len(valid_ids) - 2:
        score += 25
        feedback_parts.append('[+25] Clinical indices math correct.')
    elif math_correct >= len(valid_ids) // 2:
        score += 12
        feedback_parts.append('[+12] Clinical indices math correct for some participants (partial).')
    else:
        feedback_parts.append('[0] Clinical indices math incorrect.')
        
    if z_correct >= len(valid_ids) - 2:
        score += 20
        feedback_parts.append('[+20] Normative Z-scores mapped and calculated correctly.')
    elif z_correct >= len(valid_ids) // 2:
        score += 10
        feedback_parts.append('[+10] Normative Z-scores correct for some participants (partial).')
    else:
        feedback_parts.append('[0] Normative Z-scores incorrect.')

    # Criterion 6: Group means
    gt_means = gt.get("group_means", {})
    ag_means = report.get("group_means", {})
    mean_correct = 0
    for k, v in gt_means.items():
        ag_v = ag_means.get(k)
        if ag_v is not None:
            try:
                if abs(float(ag_v) - float(v)) < 0.1:
                    mean_correct += 1
            except (ValueError, TypeError):
                pass
            
    if mean_correct == 5:
        score += 10
        feedback_parts.append('[+10] Group means exactly match ground truth.')
    elif mean_correct >= 3:
        score += 5
        feedback_parts.append(f'[+5] {mean_correct}/5 group means match (partial).')
    else:
        feedback_parts.append(f'[0] Group means incorrect (only {mean_correct}/5 match).')

    # Overall Pass Decision
    passed = score >= 65 and acq_correct >= len(valid_ids) - 2 and exc_correct == 2
    
    if passed and score < 65:
        passed = False
        
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }