#!/usr/bin/env python3
"""Verifier for gravity_model_zone_interaction task."""

import json
import tempfile
import os

def verify_gravity_model(traj, env_info, task_info):
    """Verify gravity model zone interaction analysis was completed.
    
    Scoring (100 points total):
    - Notebook Execution & Code Patterns (20 pts)
    - Top 20 CSV Structure & Ground Truth Match (30 pts)
    - Zone Potential CSV Structure & Ground Truth Match (25 pts)
    - Population/Employment Totals Check (15 pts)
    - Heatmap Plot valid (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # Read task result JSON
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    gt = result.get('ground_truth', {})
    if 'error' in gt:
        feedback.append(f"Ground truth error: {gt['error']}")

    # 1. Notebook Execution Check (10 pts)
    nb_score = 0
    nb_a = result.get('notebook_analysis', {})
    num_exec = nb_a.get('num_executed_cells', 0)
    has_errors = nb_a.get('has_errors', True)

    if result.get('notebook_exists'):
        if num_exec >= 5 and not has_errors:
            nb_score = 10
        elif num_exec >= 3:
            nb_score = 5
        elif num_exec >= 1:
            nb_score = 2
    score += nb_score
    feedback.append(f"Notebook Exec: {nb_score}/10")

    # 2. Code Patterns Check (10 pts)
    code_score = 0
    patterns_met = 0
    if nb_a.get('has_hdf_load'): patterns_met += 1
    if nb_a.get('has_groupby'): patterns_met += 1
    if nb_a.get('has_distance'): patterns_met += 1
    if nb_a.get('has_gravity_formula'): patterns_met += 1
    if nb_a.get('has_to_csv'): patterns_met += 1
    if nb_a.get('has_heatmap'): patterns_met += 1
    
    if patterns_met >= 5: code_score = 10
    elif patterns_met >= 4: code_score = 7
    elif patterns_met >= 3: code_score = 5
    elif patterns_met >= 2: code_score = 3
    
    score += code_score
    feedback.append(f"Code Patterns: {code_score}/10")

    # 3. Top 20 CSV Check (10 pts)
    top20_csv_score = 0
    if result.get('top20_csv_exists'):
        top20_csv_score += 5
        if result.get('top20_csv_created'):
            top20_csv_score += 5
    score += top20_csv_score
    feedback.append(f"Top 20 CSV: {top20_csv_score}/10")

    # 4. Top 5 pairs match ground truth (20 pts)
    top5_score = 0
    agent_top20 = result.get('top20_data', [])
    if agent_top20 and len(agent_top20) > 0:
        gt_top5 = gt.get('top5_pairs', [])
        
        agent_top5_pairs = []
        for row in agent_top20[:5]:
            try:
                orig = int(float(row.get('origin_zone', row.get('Origin_Zone', row.get('origin', -1)))))
                dest = int(float(row.get('destination_zone', row.get('Destination_Zone', row.get('destination', -1)))))
                agent_top5_pairs.append((orig, dest))
            except (ValueError, TypeError):
                continue
        
        gt_top5_pairs = [(p['origin_zone'], p['destination_zone']) for p in gt_top5]
        
        gt_top5_set = set(gt_top5_pairs)
        agent_top5_set = set(agent_top5_pairs)
        matches = len(gt_top5_set & agent_top5_set)
        
        if matches >= 5: top5_score = 20
        elif matches >= 4: top5_score = 16
        elif matches >= 3: top5_score = 12
        elif matches >= 2: top5_score = 8
        elif matches >= 1: top5_score = 4
        
        feedback.append(f"Top 5 Pairs Match: {top5_score}/20 (Matched {matches}/5)")
    else:
        feedback.append("Top 5 Pairs Match: 0/20")
    score += top5_score

    # 5. Zone Potential CSV (10 pts)
    pot_csv_score = 0
    if result.get('potential_csv_exists'):
        pot_csv_score += 5
        if result.get('potential_csv_created'):
            pot_csv_score += 5
    score += pot_csv_score
    feedback.append(f"Potential CSV: {pot_csv_score}/10")

    # 6. Top 10 zones by potential match (15 pts)
    zone_match_score = 0
    agent_potential = result.get('potential_data', [])
    if agent_potential and len(agent_potential) > 0:
        gt_top10 = gt.get('top10_zones', [])
        gt_top10_ids = set(z['zone_id'] for z in gt_top10)
        
        agent_top10_ids = set()
        for row in agent_potential[:10]:
            try:
                zid = int(float(row.get('zone_id', row.get('Zone_ID', row.get('zone', -1)))))
                agent_top10_ids.add(zid)
            except (ValueError, TypeError):
                continue
                
        zone_matches = len(gt_top10_ids & agent_top10_ids)
        if zone_matches >= 9: zone_match_score = 15
        elif zone_matches >= 7: zone_match_score = 12
        elif zone_matches >= 5: zone_match_score = 9
        elif zone_matches >= 3: zone_match_score = 6
        elif zone_matches >= 1: zone_match_score = 3
        
        feedback.append(f"Top 10 Potential Zones Match: {zone_match_score}/15 (Matched {zone_matches}/10)")
    else:
        feedback.append("Top 10 Potential Zones Match: 0/15")
    score += zone_match_score

    # 7. Population/employment totals check (15 pts)
    totals_score = 0
    if result.get('potential_csv_exists'):
        agent_pop = result.get('total_agent_population', 0)
        agent_emp = result.get('total_agent_employment', 0)
        
        gt_pop = gt.get('total_population', 0)
        gt_emp = gt.get('total_employment', 0)
        
        pop_ok = gt_pop > 0 and (0.95 <= agent_pop / gt_pop <= 1.05)
        emp_ok = gt_emp > 0 and (0.95 <= agent_emp / gt_emp <= 1.05)
        
        if pop_ok and emp_ok: totals_score = 15
        elif pop_ok or emp_ok: totals_score = 7
        
    feedback.append(f"Totals Score: {totals_score}/15")
    score += totals_score

    # 8. Heatmap PNG (10 pts)
    hm_score = 0
    if result.get('plot_exists'):
        hm_score += 5
        if result.get('plot_created'):
            hm_score += 3
        if result.get('plot_size_kb', 0) >= 10:
            hm_score += 2
    score += hm_score
    feedback.append(f"Heatmap: {hm_score}/10")

    passed = score >= 60 and (top5_score > 0 or zone_match_score > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }