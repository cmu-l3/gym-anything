#!/usr/bin/env python3
"""
Verifier for posner_cueing_ior_analysis task.

Scoring (100 pts total):
  1. File Existence & Schema (10 pts)
  2. Artifact Exclusion: sub-99 excluded (20 pts)
  3. Error Trial Filtering: Evaluates whether accuracy==1 filter was applied (20 pts)
  4. Participant Effects: Validity effects math is correct (30 pts)
  5. Group Means: Aggregation matches correct valid participants (20 pts)

Pass threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TOLERANCE_RT = 2.0    # generous tolerance for float rounding
CONTAMINATED = "sub-99"

def verify_posner_cueing_ior_analysis(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # --- Load Export Meta ---
    meta = {}
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        meta_path = tmp.name
    try:
        copy_from_env('/tmp/posner_meta.json', meta_path)
        with open(meta_path, encoding='utf-8') as f:
            meta = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(meta_path): os.unlink(meta_path)

    # --- Criterion 1: Output file exists and is valid JSON (10 pts) ---
    if not meta.get('file_exists'):
        return {'passed': False, 'score': 0, 'feedback': 'Output file not found at ~/pebl/analysis/posner_ior_report.json'}
        
    if not meta.get('file_created_during_task'):
        feedback_parts.append('[Warning] Output file was not modified during the task duration.')

    report = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        report_path = tmp.name
    try:
        copy_from_env('/tmp/posner_result.json', report_path)
        with open(report_path, encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append('[+10] File exists and is valid JSON.')
    except (json.JSONDecodeError, ValueError) as e:
        return {'passed': False, 'score': 0, 'feedback': f'Output file is not valid JSON: {e}'}
    finally:
        if os.path.exists(report_path): os.unlink(report_path)

    # --- Load Ground Truth ---
    gt = None
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        gt_path = tmp.name
    try:
        copy_from_env('/tmp/posner_gt.json', gt_path)
        with open(gt_path, encoding='utf-8') as f:
            gt = json.load(f)
    except Exception as e:
        return {'passed': False, 'score': score, 'feedback': f'Failed to load ground truth: {e}'}
    finally:
        if os.path.exists(gt_path): os.unlink(gt_path)

    # Build participant lookup map
    part_map = {}
    for entry in report.get('participants', []):
        pid = entry.get('id') or entry.get('participant_id')
        if pid:
            part_map[str(pid)] = entry

    # --- Criterion 2: sub-99 excluded (20 pts) ---
    s99 = part_map.get(CONTAMINATED)
    is_excluded = False
    if s99 and s99.get('excluded') in (True, 'true', 1, 'yes'):
        is_excluded = True
    elif CONTAMINATED not in part_map:
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and CONTAMINATED in excluded_list:
            is_excluded = True

    if is_excluded:
        score += 20
        feedback_parts.append('[+20] Hardware artifact sub-99 correctly excluded.')
    else:
        feedback_parts.append('[0] Artifact sub-99 not excluded (impossible RTs < 50ms).')

    # --- Criteria 3 & 4: Error Trial Filtering (20 pts) and Participant Effects (30 pts) ---
    correct_filtering = 0
    correct_effects = 0
    real_ppts = [p for p in gt['participants'].keys()]
    
    for pid in real_ppts:
        entry = part_map.get(pid)
        if not entry or entry.get('excluded'): continue
        
        # Check Error Filtering via mean RTs
        means = entry.get('mean_rt', {})
        if means:
            try:
                sv = float(means.get('short_soa_valid', means.get('short_valid', 0)))
                # Compare against GT
                gt_filtered = gt['participants'][pid]['filtered_means']['short_valid']
                gt_unfiltered = gt['participants'][pid]['unfiltered_means']['short_valid']
                
                diff_filtered = abs(sv - gt_filtered)
                diff_unfiltered = abs(sv - gt_unfiltered)
                
                if diff_filtered <= TOLERANCE_RT:
                    correct_filtering += 1
            except (ValueError, TypeError):
                pass

        # Check Effects Math
        effects = entry.get('effects', {})
        if not effects:
            # Maybe flat format
            effects = entry

        try:
            s_eff = float(effects.get('short_soa_validity_effect', 0))
            l_eff = float(effects.get('long_soa_validity_effect', 0))
            
            gt_s_eff = gt['participants'][pid]['short_soa_validity_effect']
            gt_l_eff = gt['participants'][pid]['long_soa_validity_effect']
            
            if abs(s_eff - gt_s_eff) <= TOLERANCE_RT and abs(l_eff - gt_l_eff) <= TOLERANCE_RT:
                correct_effects += 1
        except (ValueError, TypeError):
            pass

    # Score Filtering
    if correct_filtering >= 20:
        score += 20
        feedback_parts.append('[+20] Error trials correctly filtered out prior to RT aggregation.')
    elif correct_filtering > 0:
        score += 10
        feedback_parts.append('[+10] Error trial filtering partially correct.')
    else:
        feedback_parts.append('[0] RTs incorrect (Did you forget to filter accuracy == 1?).')

    # Score Effects
    if correct_effects >= 20:
        score += 30
        feedback_parts.append('[+30] Validity effects computed accurately.')
    elif correct_effects > 0:
        score += 15
        feedback_parts.append('[+15] Validity effects computed partially correctly.')
    else:
        feedback_parts.append('[0] Validity effects missing or math incorrect.')

    # --- Criterion 5: Group Means (20 pts) ---
    group_means = report.get('group_means', {})
    try:
        s_gm = float(group_means.get('short_soa_validity_effect', 0))
        l_gm = float(group_means.get('long_soa_validity_effect', 0))
        
        gt_s_gm = gt['group_means']['short_soa_validity_effect']
        gt_l_gm = gt['group_means']['long_soa_validity_effect']
        
        if abs(s_gm - gt_s_gm) <= TOLERANCE_RT and abs(l_gm - gt_l_gm) <= TOLERANCE_RT:
            score += 20
            feedback_parts.append('[+20] Group means aggregated accurately.')
        else:
            feedback_parts.append('[0] Group means incorrect (Make sure sub-99 is excluded from aggregation).')
    except (ValueError, TypeError):
        feedback_parts.append('[0] Group means missing or invalid format.')

    passed = score >= 60 and is_excluded

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }