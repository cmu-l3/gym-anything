#!/usr/bin/env python3
"""Verifier for crispr_knockout_screen task."""

import json
import tempfile
import os


def verify_crispr_knockout_screen(traj, env_info, task_info):
    """Verify full CRISPR screen ELN documentation setup."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/crispr_knockout_screen_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1 (10 pts): Project found with correct name ---
    project_found = result.get('project_found', False)
    if project_found:
        score += 10
        feedback.append("Project 'CRISPR Knockout Screen - KRAS' found (10/10)")
    else:
        feedback.append("Project 'CRISPR Knockout Screen - KRAS' NOT found (0/10)")
        # Cannot score anything else without the project
        return {"passed": False, "score": 0,
                "feedback": " | ".join(feedback),
                "subscores": {"project": False}}

    # --- Criterion 2 (10 pts): sgRNA Library Synthesis experiment ---
    exp1_found = result.get('experiment_sgrna_found', False)
    if exp1_found:
        score += 10
        feedback.append("Experiment 'sgRNA Library Synthesis' found (10/10)")
    else:
        feedback.append("Experiment 'sgRNA Library Synthesis' NOT found (0/10)")

    # --- Criterion 3 (10 pts): Cell Line Engineering experiment ---
    exp2_found = result.get('experiment_cell_found', False)
    if exp2_found:
        score += 10
        feedback.append("Experiment 'Cell Line Engineering' found (10/10)")
    else:
        feedback.append("Experiment 'Cell Line Engineering' NOT found (0/10)")

    # --- Criterion 4 (15 pts): 3 tasks in sgRNA Library Synthesis ---
    exp1_tasks = result.get('exp1_tasks', [])
    exp1_task_lower = [t.lower() for t in exp1_tasks]
    task_oligo = any('oligo' in t and 'design' in t for t in exp1_task_lower)
    task_pcr = any('pcr' in t and 'amplif' in t for t in exp1_task_lower)
    task_cloning = any('library' in t and 'clon' in t for t in exp1_task_lower)

    exp1_score = 0
    if task_oligo:
        exp1_score += 5
        feedback.append("Task 'Oligo Design and Ordering' found")
    else:
        feedback.append("Task 'Oligo Design and Ordering' NOT found")
    if task_pcr:
        exp1_score += 5
        feedback.append("Task 'PCR Amplification' found")
    else:
        feedback.append("Task 'PCR Amplification' NOT found")
    if task_cloning:
        exp1_score += 5
        feedback.append("Task 'Library Cloning' found")
    else:
        feedback.append("Task 'Library Cloning' NOT found")
    score += exp1_score

    # --- Criterion 5 (10 pts): 2 tasks in Cell Line Engineering ---
    exp2_tasks = result.get('exp2_tasks', [])
    exp2_task_lower = [t.lower() for t in exp2_tasks]
    task_lenti = any('lentiviral' in t and 'prod' in t for t in exp2_task_lower)
    task_trans = any('cell' in t and 'transduct' in t for t in exp2_task_lower)

    exp2_score = 0
    if task_lenti:
        exp2_score += 5
        feedback.append("Task 'Lentiviral Production' found")
    else:
        feedback.append("Task 'Lentiviral Production' NOT found")
    if task_trans:
        exp2_score += 5
        feedback.append("Task 'Cell Transduction and Selection' found")
    else:
        feedback.append("Task 'Cell Transduction and Selection' NOT found")
    score += exp2_score

    # --- Criterion 6 (10 pts): Connection Oligo → PCR ---
    conn_oligo_pcr = result.get('conn_oligo_to_pcr', False)
    if conn_oligo_pcr:
        score += 10
        feedback.append("Connection 'Oligo Design' → 'PCR Amplification' found (10/10)")
    else:
        feedback.append("Connection 'Oligo Design' → 'PCR Amplification' NOT found (0/10)")

    # --- Criterion 7 (10 pts): Connection PCR → Library Cloning ---
    conn_pcr_clon = result.get('conn_pcr_to_cloning', False)
    if conn_pcr_clon:
        score += 10
        feedback.append("Connection 'PCR Amplification' → 'Library Cloning' found (10/10)")
    else:
        feedback.append("Connection 'PCR Amplification' → 'Library Cloning' NOT found (0/10)")

    # --- Criterion 8 (5 pts): Connection Lenti → Transduction ---
    conn_lenti_trans = result.get('conn_lenti_to_transduction', False)
    if conn_lenti_trans:
        score += 5
        feedback.append("Connection 'Lentiviral Production' → 'Cell Transduction' found (5/5)")
    else:
        feedback.append("Connection 'Lentiviral Production' → 'Cell Transduction' NOT found (0/5)")

    # --- Criterion 9 (10 pts): ≥6 steps in Lentiviral Production protocol ---
    step_count = int(result.get('lentiviral_protocol_step_count', 0))
    if step_count >= 6:
        score += 10
        feedback.append(f"Lentiviral Production protocol has {step_count} steps (≥6 required) (10/10)")
    elif step_count >= 3:
        score += 5
        feedback.append(f"Lentiviral Production protocol has {step_count} steps (partial, need ≥6) (5/10)")
    else:
        feedback.append(f"Lentiviral Production protocol has only {step_count} steps (need ≥6) (0/10)")

    # --- Criterion 10 (5 pts): Inventory 'CRISPR Screen Reagents' found ---
    inv_found = result.get('inventory_found', False)
    if inv_found:
        score += 5
        feedback.append("Inventory 'CRISPR Screen Reagents' found (5/5)")
    else:
        feedback.append("Inventory 'CRISPR Screen Reagents' NOT found (0/5)")

    # --- Criterion 11 (5 pts): Inventory has ≥4 columns ---
    col_count = int(result.get('inventory_column_count', 0))
    if col_count >= 4:
        score += 5
        feedback.append(f"Inventory has {col_count} columns (≥4 required) (5/5)")
    else:
        feedback.append(f"Inventory has only {col_count} columns (need ≥4) (0/5)")

    # Total: 100 pts; pass at 60
    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "project_found": project_found,
            "exp_sgrna_found": exp1_found,
            "exp_cell_found": exp2_found,
            "tasks_exp1": exp1_score,
            "tasks_exp2": exp2_score,
            "conn_oligo_pcr": conn_oligo_pcr,
            "conn_pcr_cloning": conn_pcr_clon,
            "conn_lenti_trans": conn_lenti_trans,
            "protocol_steps": step_count,
            "inventory_found": inv_found,
            "columns_count": col_count
        }
    }
