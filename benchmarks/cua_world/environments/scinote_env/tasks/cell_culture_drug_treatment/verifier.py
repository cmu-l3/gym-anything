#!/usr/bin/env python3
"""Verifier for cell_culture_drug_treatment task."""

import json
import tempfile
import os


def verify_cell_culture_drug_treatment(traj, env_info, task_info):
    """Verify dose-response drug study ELN completion: tasks, connections, protocol, expanded inventory."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cell_culture_drug_treatment_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    all_tasks_lower = [t.lower() for t in result.get('all_tasks', [])]
    task_count = int(result.get('task_count', 0))

    # --- Criterion 1 (15 pts): Both new tasks exist ---
    has_drug = any('drug' in t and 'treat' in t for t in all_tasks_lower)
    has_anal = any('data' in t and 'anal' in t for t in all_tasks_lower)

    if has_drug:
        score += 8
        feedback.append("Task 'Drug Treatment' found (8/8)")
    else:
        feedback.append("Task 'Drug Treatment' NOT found (0/8)")
    if has_anal:
        score += 7
        feedback.append("Task 'Data Analysis' found (7/7)")
    else:
        feedback.append("Task 'Data Analysis' NOT found (0/7)")

    # --- Criterion 2 (10 pts): Total task count is 4 ---
    if task_count >= 4:
        score += 10
        feedback.append(f"Experiment has {task_count} tasks (≥4) (10/10)")
    elif task_count == 3:
        score += 5
        feedback.append(f"Experiment has {task_count} tasks (partial, need 4) (5/10)")
    else:
        feedback.append(f"Experiment has {task_count} tasks (need 4) (0/10)")

    # --- Criterion 3 (15 pts): Connection Cell Seeding → Drug Treatment ---
    conn1 = result.get('conn_seed_to_drug', False)
    if conn1:
        score += 15
        feedback.append("Connection 'Cell Seeding' → 'Drug Treatment' found (15/15)")
    else:
        feedback.append("Connection 'Cell Seeding' → 'Drug Treatment' NOT found (0/15)")

    # --- Criterion 4 (15 pts): Connection Drug Treatment → Cell Viability Assay ---
    conn2 = result.get('conn_drug_to_viab', False)
    if conn2:
        score += 15
        feedback.append("Connection 'Drug Treatment' → 'Cell Viability Assay' found (15/15)")
    else:
        feedback.append("Connection 'Drug Treatment' → 'Cell Viability Assay' NOT found (0/15)")

    # --- Criterion 5 (10 pts): Connection Cell Viability Assay → Data Analysis ---
    conn3 = result.get('conn_viab_to_anal', False)
    if conn3:
        score += 10
        feedback.append("Connection 'Cell Viability Assay' → 'Data Analysis' found (10/10)")
    else:
        feedback.append("Connection 'Cell Viability Assay' → 'Data Analysis' NOT found (0/10)")

    # --- Criterion 6 (10 pts): ≥5 steps in Drug Treatment protocol ---
    step_count = int(result.get('drug_treatment_step_count', 0))
    if step_count >= 5:
        score += 10
        feedback.append(f"Drug Treatment protocol has {step_count} steps (≥5) (10/10)")
    elif step_count >= 3:
        score += 5
        feedback.append(f"Drug Treatment protocol has {step_count} steps (partial) (5/10)")
    else:
        feedback.append(f"Drug Treatment protocol has {step_count} steps (need ≥5) (0/10)")

    # --- Criterion 7 (10 pts): 2 new columns added ---
    has_solvent = result.get('has_solvent_column', False)
    has_storage = result.get('has_storage_column', False)
    if has_solvent:
        score += 5
        feedback.append("Column 'Solvent' found (5/5)")
    else:
        feedback.append("Column 'Solvent' NOT found (0/5)")
    if has_storage:
        score += 5
        feedback.append("Column 'Storage Conditions' found (5/5)")
    else:
        feedback.append("Column 'Storage Conditions' NOT found (0/5)")

    # --- Criterion 8 (15 pts): 3 drug items with concentration and solvent ---
    items = result.get('inventory_items', [])
    item_map = {it.get('name', '').lower(): it for it in items}
    item_count = int(result.get('inventory_item_count', 0))

    expected_drugs = [
        ('doxorubicin', 'DMSO'),
        ('cisplatin', 'Saline'),
        ('paclitaxel', 'DMSO'),
    ]
    drugs_found = 0
    solvents_ok = 0
    for drug_kw, exp_solvent in expected_drugs:
        match = next((n for n in item_map if drug_kw in n), None)
        if match:
            drugs_found += 1
            actual_solvent = item_map[match].get('solvent', '').strip()
            if actual_solvent.lower() == exp_solvent.lower():
                solvents_ok += 1

    item_pts = drugs_found * 3 + solvents_ok * 2
    item_pts = min(item_pts, 15)
    score += item_pts
    feedback.append(f"Drug items: {drugs_found}/3 found, {solvents_ok}/3 solvents correct ({item_pts}/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "drug_task": has_drug,
            "analysis_task": has_anal,
            "task_count": task_count,
            "conn1": conn1,
            "conn2": conn2,
            "conn3": conn3,
            "protocol_steps": step_count,
            "solvent_col": has_solvent,
            "storage_col": has_storage,
            "drugs_found": drugs_found,
            "solvents_correct": solvents_ok
        }
    }
