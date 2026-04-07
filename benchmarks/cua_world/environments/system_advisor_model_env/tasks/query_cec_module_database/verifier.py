#!/usr/bin/env python3
"""
Verifier for query_cec_module_database task.

Ensures the agent successfully queried the SAM CEC Modules database,
filtered the data correctly, sorted it, and exported authentic results.
"""

import json
import tempfile
import os
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_query_cec_module_database(traj, env_info, task_info):
    """
    Verify the JSON output of the CEC module database query.
    
    Scoring System (100 points total):
    - File exists & valid JSON: 10
    - File created during task (anti-gaming): 10
    - Correct JSON structure: 10
    - Exactly 15 entries: 5
    - Filtering rules (Pmp, Eff, Mono): 25 (10+10+5)
    - Sorted correctly: 10
    - Name authenticity (matches real DB): 15
    - Mathematical accuracy (Efficiency calculation): 10
    - Count sanity check: 5
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SAM_Projects/premium_modules_report.json')
    min_pmp_w = metadata.get('min_pmp_w', 380)
    min_efficiency_pct = metadata.get('min_efficiency_pct', 20.0)
    req_tech = metadata.get('required_technology', 'mono').lower()
    
    # 1. Load the task metadata result
    meta_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    task_meta = {}
    try:
        copy_from_env("/tmp/task_result.json", meta_temp.name)
        with open(meta_temp.name, 'r') as f:
            task_meta = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task metadata: {e}")
    finally:
        if os.path.exists(meta_temp.name):
            os.unlink(meta_temp.name)

    file_exists = task_meta.get('file_exists', False)
    file_modified = task_meta.get('file_modified', False)
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Expected output JSON file was not found."}
    
    # 2. Load the agent's actual JSON output
    report_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    agent_data = None
    try:
        copy_from_env(expected_path, report_temp.name)
        with open(report_temp.name, 'r') as f:
            agent_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Output file is not valid JSON: {e}"}
    finally:
        if os.path.exists(report_temp.name):
            os.unlink(report_temp.name)
            
    score += 10
    feedback_parts.append("Valid JSON file found")

    if file_modified:
        score += 10
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("File timestamp predates task start (possible stale file)")

    # 3. Check JSON Structure
    has_criteria = "query_criteria" in agent_data
    has_total = "total_modules_matching" in agent_data
    has_top_15 = "top_15_modules" in agent_data and isinstance(agent_data.get("top_15_modules"), list)
    
    if has_criteria and has_total and has_top_15:
        score += 10
        feedback_parts.append("Correct JSON base structure")
    else:
        feedback_parts.append("Missing required top-level JSON keys")
        
    top_15 = agent_data.get("top_15_modules", [])
    if len(top_15) == 15:
        score += 5
        feedback_parts.append("Exactly 15 modules returned")
    elif len(top_15) > 0:
        feedback_parts.append(f"Returned {len(top_15)} modules instead of 15")
    else:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Empty module list"}

    # 4. Check Filtering Rules
    all_pmp_pass = True
    all_eff_pass = True
    all_tech_pass = True
    required_keys = ['name', 'pmp_w', 'efficiency_pct', 'area_m2', 'technology']
    
    for mod in top_15:
        if not all(k in mod for k in required_keys):
            continue
            
        pmp = float(mod.get('pmp_w', 0))
        eff = float(mod.get('efficiency_pct', 0))
        tech = str(mod.get('technology', '')).lower()
        
        if pmp < min_pmp_w: all_pmp_pass = False
        if eff < min_efficiency_pct: all_eff_pass = False
        if req_tech not in tech: all_tech_pass = False

    if all_pmp_pass:
        score += 10
        feedback_parts.append(f"All modules meet Pmp >= {min_pmp_w}W")
    if all_eff_pass:
        score += 10
        feedback_parts.append(f"All modules meet Efficiency >= {min_efficiency_pct}%")
    if all_tech_pass:
        score += 5
        feedback_parts.append(f"All modules are Monocrystalline")

    # 5. Check Sorting (Efficiency descending)
    efficiencies = [float(m.get('efficiency_pct', 0)) for m in top_15 if 'efficiency_pct' in m]
    if len(efficiencies) > 1 and all(efficiencies[i] >= efficiencies[i+1] for i in range(len(efficiencies)-1)):
        score += 10
        feedback_parts.append("Modules correctly sorted by efficiency (descending)")
    else:
        feedback_parts.append("Sorting incorrect or missing efficiency values")

    # 6. Load Ground Truth CEC DB to check authenticity
    gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    valid_db_cells = set()
    try:
        copy_from_env("/tmp/ground_truth_cec.csv", gt_temp.name)
        with open(gt_temp.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.reader(f)
            for row in reader:
                for cell in row:
                    valid_db_cells.add(cell.strip().lower())
    except Exception as e:
        logger.warning(f"Failed to read ground truth CEC database: {e}")
    finally:
        if os.path.exists(gt_temp.name):
            os.unlink(gt_temp.name)

    # 7. Check Name Authenticity (Anti-gaming)
    authentic_count = 0
    if valid_db_cells:
        for mod in top_15:
            name = str(mod.get('name', '')).strip().lower()
            if name in valid_db_cells:
                authentic_count += 1
        
        if authentic_count >= 12:
            score += 15
            feedback_parts.append(f"Authentic module names ({authentic_count}/{len(top_15)})")
        elif authentic_count > 0:
            score += int(15 * (authentic_count / 12))
            feedback_parts.append(f"Some fabricated module names ({authentic_count}/{len(top_15)} authentic)")
        else:
            feedback_parts.append("Fabricated module names detected (not in CEC database)")
    else:
        # Give benefit of doubt if DB couldn't be loaded for some reason
        score += 15
        feedback_parts.append("Skipped authenticity check (DB missing)")

    # 8. Check Mathematical Accuracy (Anti-gaming)
    # Efficiency roughly equals Pmp / (Area * 10) at STC (1000 W/m2)
    math_accurate_count = 0
    math_checks_done = 0
    for mod in top_15:
        pmp = float(mod.get('pmp_w', 0))
        area = float(mod.get('area_m2', 0))
        eff = float(mod.get('efficiency_pct', 0))
        
        if area > 0 and pmp > 0:
            math_checks_done += 1
            calculated_eff = pmp / (area * 10)
            # Allow 1% tolerance due to rounding in different CEC columns
            if abs(calculated_eff - eff) < 1.0:
                math_accurate_count += 1

    if math_checks_done > 0:
        if math_accurate_count / math_checks_done >= 0.8:
            score += 10
            feedback_parts.append("Efficiency math cross-checks pass")
        else:
            feedback_parts.append(f"Efficiency math inconsistent (Pmp/Area mismatch in {math_checks_done - math_accurate_count} entries)")
    else:
        feedback_parts.append("Missing area or pmp values for math check")

    # 9. Count sanity check
    total_matching = agent_data.get("total_modules_matching", 0)
    if isinstance(total_matching, int) and 50 <= total_matching <= 5000:
        score += 5
        feedback_parts.append("Total matching count in plausible range")
    else:
        feedback_parts.append(f"Implausible matching count ({total_matching})")

    # Determine Pass/Fail
    # Minimum 70 points AND must have authentic names AND file must exist
    is_authentic = valid_db_cells is set() or authentic_count >= 12
    passed = score >= 70 and file_exists and is_authentic

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }