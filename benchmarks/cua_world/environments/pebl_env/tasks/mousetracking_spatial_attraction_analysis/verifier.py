#!/usr/bin/env python3
"""
Verifier for mousetracking_spatial_attraction_analysis task.

Scoring (100 pts total):
  1. Output file exists and is valid JSON (10 pts)
  2. Participant p99 correctly excluded (robotic linear artifact) (20 pts)
  3. Mean MD Competitor accurate within ±2.0 for ≥80% valid ppts (20 pts)
  4. Mean MD Unrelated accurate within ±2.0 for ≥80% valid ppts (20 pts)
  5. Individual Attraction Effects accurate within ±2.0 for ≥80% valid ppts (15 pts)
  6. Group Mean Attraction Effect accurate within ±1.5 (15 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ARTIFACT_ID = 'p99'
TOLERANCE_MD = 2.0
TOLERANCE_GROUP = 1.5

def verify_mousetracking_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Fetch Ground Truth
    gt_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_gt:
        gt_path = tmp_gt.name

    try:
        copy_from_env('/opt/pebl/.hidden_mousetracking_gt.json', gt_path)
        with open(gt_path, 'r', encoding='utf-8') as f:
            gt_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}
    finally:
        if os.path.exists(gt_path):
            os.unlink(gt_path)

    # 2. Fetch Agent's Report
    report_data = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp_rep:
        rep_path = tmp_rep.name

    try:
        copy_from_env('/home/ga/pebl/analysis/mousetracking_report.json', rep_path)
        with open(rep_path, 'r', encoding='utf-8') as f:
            report_data = json.load(f)
        score += 10
        feedback_parts.append('[+10] Report file found and is valid JSON.')
    except FileNotFoundError:
        feedback_parts.append('[0] Report file not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    except (json.JSONDecodeError, ValueError) as e:
        feedback_parts.append(f'[0] Report is not valid JSON: {e}')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}
    finally:
        if os.path.exists(rep_path):
            os.unlink(rep_path)

    participants_list = report_data.get('participants', [])
    if not isinstance(participants_list, list):
        feedback_parts.append('[0] "participants" key missing or not a list.')
        return {'passed': False, 'score': score, 'feedback': ' '.join(feedback_parts)}

    part_map = {}
    for entry in participants_list:
        pid = entry.get('id') or entry.get('participant_id') or entry.get('participant')
        if pid:
            part_map[str(pid)] = entry

    def is_excluded(pid):
        entry = part_map.get(pid)
        if entry and entry.get('excluded') in (True, 'true', 1, 'yes'):
            return True
        if entry and entry.get('flagged') in (True, 'true', 1, 'yes'):
            return True
        if pid not in part_map:
            excluded_list = report_data.get('excluded', [])
            if isinstance(excluded_list, list) and pid in excluded_list:
                return True
        return False

    # 3. Check Exclusion
    if is_excluded(ARTIFACT_ID):
        score += 20
        feedback_parts.append(f'[+20] Artifact {ARTIFACT_ID} correctly excluded.')
    else:
        feedback_parts.append(f'[0] Artifact {ARTIFACT_ID} not excluded (should have been due to robotic linear lines).')

    # 4. Check Per-Participant MDs
    correct_comp = 0
    correct_unrel = 0
    correct_effect = 0
    
    gt_participants = gt_data.get('participants', {})
    valid_count = len(gt_participants)

    for pid, gt_vals in gt_participants.items():
        entry = part_map.get(pid)
        if entry is None or is_excluded(pid):
            continue
            
        # Extract Agent Values
        comp_md = entry.get('mean_md_competitor')
        unrel_md = entry.get('mean_md_unrelated')
        effect = entry.get('attraction_effect')
        
        # Competitor Check
        if comp_md is not None:
            try:
                if abs(float(comp_md) - gt_vals['mean_md_competitor']) <= TOLERANCE_MD:
                    correct_comp += 1
            except ValueError: pass
            
        # Unrelated Check
        if unrel_md is not None:
            try:
                if abs(float(unrel_md) - gt_vals['mean_md_unrelated']) <= TOLERANCE_MD:
                    correct_unrel += 1
            except ValueError: pass
            
        # Effect Check
        if effect is not None:
            try:
                if abs(float(effect) - gt_vals['attraction_effect']) <= TOLERANCE_MD:
                    correct_effect += 1
            except ValueError: pass

    # Scoring Computations based on >= 80% accuracy
    threshold = int(valid_count * 0.8)
    
    if correct_comp >= threshold:
        score += 20
        feedback_parts.append(f'[+20] Competitor MD accurate for {correct_comp}/{valid_count} participants.')
    else:
        feedback_parts.append(f'[0] Competitor MD accurate for {correct_comp}/{valid_count} participants.')
        
    if correct_unrel >= threshold:
        score += 20
        feedback_parts.append(f'[+20] Unrelated MD accurate for {correct_unrel}/{valid_count} participants.')
    else:
        feedback_parts.append(f'[0] Unrelated MD accurate for {correct_unrel}/{valid_count} participants.')
        
    if correct_effect >= threshold:
        score += 15
        feedback_parts.append(f'[+15] Attraction Effect accurate for {correct_effect}/{valid_count} participants.')
    else:
        feedback_parts.append(f'[0] Attraction Effect accurate for {correct_effect}/{valid_count} participants.')

    # 5. Check Group Mean
    group_mean = report_data.get('group_mean_attraction_effect')
    gt_group_mean = gt_data.get('group_mean_attraction_effect', 0.0)
    
    if group_mean is not None:
        try:
            if abs(float(group_mean) - gt_group_mean) <= TOLERANCE_GROUP:
                score += 15
                feedback_parts.append(f'[+15] Group Mean ({group_mean}) within tolerance of GT ({gt_group_mean}).')
            else:
                feedback_parts.append(f'[0] Group Mean ({group_mean}) not within tolerance of GT ({gt_group_mean}).')
        except ValueError:
            feedback_parts.append('[0] Group mean is not a valid number.')
    else:
        feedback_parts.append('[0] group_mean_attraction_effect missing.')

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }