#!/usr/bin/env python3
"""Verifier for property_tax_revenue_projection task."""

import json
import tempfile
import os
import math


def verify_tax_revenue_projection(traj, env_info, task_info):
    """Verify property tax analysis was completed successfully.

    Scoring (100 points total):
    - 10 pts: CSV exists with required columns
    - 10 pts: Zone count accuracy (>=80% of true zones)
    - 15 pts: Total assessed value accuracy (+/- 5%)
    - 15 pts: Tax calculation correctness (assessed * 0.0117 == tax)
    - 10 pts: Top zone ranking agreement (>=3 of top 5 match)
    - 10 pts: Tax per acre correctly mapped and positive
    - 10 pts: Bar chart PNG is valid
    - 10 pts: Notebook code patterns (merge, groupby, tax rate)
    - 5 pts: Notebook execution (>=6 cells)
    - 5 pts: File creation anti-gaming (created during task)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tax_rate = metadata.get('tax_rate', 0.0117)
    
    score = 0
    feedback = []

    # Read result from container
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Variables for grading
    gt = result.get('ground_truth', {})
    agt = result.get('agent_totals', {})
    nba = result.get('notebook_analysis', {})
    
    gt_assessed = gt.get('total_assessed', 0)
    gt_tax = gt.get('total_tax', 0)
    gt_zone_count = gt.get('zone_count', 0)
    gt_top5 = gt.get('top5_zones', [])
    
    agent_assessed = agt.get('total_assessed', 0)
    agent_tax = agt.get('total_tax', 0)
    agent_zone_count = agt.get('zone_count', 0)
    agent_top5 = agt.get('top5_zones', [])

    # 1. CSV Existence & Columns (10 pts)
    csv_cols = result.get('csv_columns', [])
    req_cols_found = sum([
        1 for keyword in ['zone', 'assessed', 'tax', 'acre', 'building'] 
        if any(keyword in col for col in csv_cols)
    ])
    
    if result.get('csv_exists'):
        if req_cols_found >= 4:
            score += 10
            feedback.append("CSV columns are valid")
        else:
            score += 5
            feedback.append("CSV exists but missing some required columns")
    else:
        feedback.append("Missing CSV output")

    # 2. Zone count accuracy (10 pts)
    if gt_zone_count > 0 and agent_zone_count > 0:
        if agent_zone_count >= (gt_zone_count * 0.8) and agent_zone_count <= (gt_zone_count * 1.2):
            score += 10
            feedback.append("Zone count is accurate")
        else:
            feedback.append(f"Zone count mismatch (Agent: {agent_zone_count}, Expected: ~{gt_zone_count})")
    
    # 3. Total assessed value accuracy (15 pts)
    assessed_accuracy_met = False
    if gt_assessed > 0 and agent_assessed > 0:
        error_margin = abs(gt_assessed - agent_assessed) / gt_assessed
        if error_margin <= 0.05:
            score += 15
            assessed_accuracy_met = True
            feedback.append("Total assessed value is accurate")
        else:
            feedback.append(f"Total assessed value error too high ({error_margin:.1%})")

    # 4. Tax calculation correctness (15 pts)
    if agent_assessed > 0 and agent_tax > 0:
        implied_rate = agent_tax / agent_assessed
        if math.isclose(implied_rate, tax_rate, rel_tol=0.01):
            score += 15
            feedback.append("Tax rate applied correctly")
        else:
            feedback.append(f"Incorrect tax rate applied (Implied: {implied_rate:.4f})")

    # 5. Top zone ranking agreement (10 pts)
    if gt_top5 and agent_top5:
        matches = len(set(gt_top5).intersection(set(agent_top5)))
        if matches >= 3:
            score += 10
            feedback.append(f"Top zones identified correctly ({matches}/5 match)")
        elif matches > 0:
            score += 5
            feedback.append(f"Partial top zones match ({matches}/5)")

    # 6. Tax per acre positive count (10 pts)
    pos_tax_acre = agt.get('positive_tax_per_acre_count', 0)
    if pos_tax_acre > (gt_zone_count * 0.5):
        score += 10
        feedback.append("Tax per acre calculated successfully")
    elif pos_tax_acre > 0:
        score += 5

    # 7. Bar chart valid (10 pts)
    if result.get('plot_exists'):
        if result.get('plot_size_kb', 0) >= 5:
            score += 10
            feedback.append("Plot created successfully")
        else:
            score += 5
            feedback.append("Plot created but file size is suspiciously small")
            
    # 8. Notebook code patterns (10 pts)
    patterns_score = 0
    if nba.get('has_pandas'): patterns_score += 2
    if nba.get('has_merge'): patterns_score += 2
    if nba.get('has_groupby'): patterns_score += 2
    if nba.get('has_tax_rate'): patterns_score += 2
    if nba.get('has_bar_plot'): patterns_score += 2
    score += patterns_score
    feedback.append(f"Code patterns: {patterns_score}/10")

    # 9. Notebook execution (5 pts)
    num_exec = nba.get('num_executed_cells', 0)
    if num_exec >= 6:
        score += 5
    elif num_exec >= 3:
        score += 2
        
    # 10. File creation timestamps anti-gaming (5 pts)
    if result.get('csv_created') and result.get('plot_created'):
        score += 5

    # Threshold criteria
    passed = score >= 60 and assessed_accuracy_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }