#!/usr/bin/env python3
"""Verifier for rnaseq_qc_documentation task."""

import json
import tempfile
import os


def verify_rnaseq_qc_documentation(traj, env_info, task_info):
    """Verify full RNA-seq QC pipeline ELN documentation setup."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rnaseq_qc_documentation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1 (10 pts): Project found ---
    project_found = result.get('project_found', False)
    if project_found:
        score += 10
        feedback.append("Project 'RNA-seq Quality Control Pipeline' found (10/10)")
    else:
        feedback.append("Project 'RNA-seq Quality Control Pipeline' NOT found (0/10)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback),
                "subscores": {"project": False}}

    # --- Criterion 2 (8 pts): Library QC Assessment experiment ---
    exp1_found = result.get('exp1_found', False)
    if exp1_found:
        score += 8
        feedback.append("Experiment 'Library QC Assessment' found (8/8)")
    else:
        feedback.append("Experiment 'Library QC Assessment' NOT found (0/8)")

    # --- Criterion 3 (7 pts): Bioinformatics Pipeline experiment ---
    exp2_found = result.get('exp2_found', False)
    if exp2_found:
        score += 7
        feedback.append("Experiment 'Bioinformatics Pipeline' found (7/7)")
    else:
        feedback.append("Experiment 'Bioinformatics Pipeline' NOT found (0/7)")

    # --- Criterion 4 (20 pts): 4 tasks in Library QC Assessment ---
    exp1_tasks = [t.lower() for t in result.get('exp1_tasks', [])]
    t_extract = any('rna' in t and 'extract' in t for t in exp1_tasks)
    t_quality = any('rna' in t and 'quality' in t for t in exp1_tasks)
    t_libprep = any('library' in t and 'prep' in t for t in exp1_tasks)
    t_quant = any('library' in t and 'quant' in t for t in exp1_tasks)

    for has, name in [(t_extract, 'RNA Extraction'), (t_quality, 'RNA Quality Assessment'),
                      (t_libprep, 'Library Preparation'), (t_quant, 'Library Quantification')]:
        if has:
            score += 5
            feedback.append(f"Task '{name}' found")
        else:
            feedback.append(f"Task '{name}' NOT found")

    # --- Criterion 5 (15 pts): 3 tasks in Bioinformatics Pipeline ---
    exp2_tasks = [t.lower() for t in result.get('exp2_tasks', [])]
    t_trim = any('read' in t and 'trim' in t for t in exp2_tasks)
    t_align = any('reference' in t and 'align' in t for t in exp2_tasks)
    t_quant2 = any('expression' in t and 'quant' in t for t in exp2_tasks)

    for has, name in [(t_trim, 'Read Trimming'), (t_align, 'Reference Alignment'),
                      (t_quant2, 'Expression Quantification')]:
        if has:
            score += 5
            feedback.append(f"Task '{name}' found")
        else:
            feedback.append(f"Task '{name}' NOT found")

    # --- Criterion 6 (15 pts): Connections in experiment 1 ---
    c1 = result.get('conn_extract_quality', False)
    c2 = result.get('conn_quality_libprep', False)
    c3 = result.get('conn_libprep_quant', False)
    for has, name in [(c1, 'RNA Extraction→Quality Assessment'), (c2, 'Quality Assessment→Library Prep'),
                      (c3, 'Library Prep→Quantification')]:
        if has:
            score += 5
            feedback.append(f"Connection '{name}' found")
        else:
            feedback.append(f"Connection '{name}' NOT found")

    # --- Criterion 7 (10 pts): Connections in experiment 2 ---
    c4 = result.get('conn_trim_align', False)
    c5 = result.get('conn_align_quant', False)
    for has, name in [(c4, 'Read Trimming→Reference Alignment'), (c5, 'Reference Alignment→Expression Quant')]:
        if has:
            score += 5
            feedback.append(f"Connection '{name}' found")
        else:
            feedback.append(f"Connection '{name}' NOT found")

    # --- Criterion 8 (10 pts): ≥6 steps in Library Preparation protocol ---
    step_count = int(result.get('libprep_protocol_step_count', 0))
    if step_count >= 6:
        score += 10
        feedback.append(f"Library Preparation protocol has {step_count} steps (≥6) (10/10)")
    elif step_count >= 3:
        score += 5
        feedback.append(f"Library Preparation protocol has {step_count} steps (partial) (5/10)")
    else:
        feedback.append(f"Library Preparation protocol has {step_count} steps (need ≥6) (0/10)")

    # --- Criterion 9 (5 pts): Inventory found ---
    inv_found = result.get('inventory_found', False)
    if inv_found:
        score += 5
        feedback.append("Inventory 'RNA-seq Reagents' found (5/5)")
    else:
        feedback.append("Inventory 'RNA-seq Reagents' NOT found (0/5)")

    # --- Criterion 10 (5 pts): ≥4 columns ---
    col_count = int(result.get('inventory_column_count', 0))
    if col_count >= 4:
        score += 5
        feedback.append(f"Inventory has {col_count} columns (≥4) (5/5)")
    else:
        feedback.append(f"Inventory has {col_count} columns (need ≥4) (0/5)")

    # --- Criterion 11 (up to 5 pts): ≥4 items ---
    item_count = int(result.get('inventory_item_count', 0))
    items = [i.lower() for i in result.get('inventory_items', [])]
    expected_kw = ['rneasy', 'kapa', 'ercc', 'dnase']
    items_matched = sum(1 for kw in expected_kw if any(kw in i for i in items))

    if items_matched >= 4:
        score += 5
        feedback.append(f"All 4 expected reagents found in inventory (5/5)")
    elif items_matched >= 2:
        score += 2
        feedback.append(f"{items_matched}/4 expected reagents found in inventory (2/5)")
    else:
        feedback.append(f"{items_matched}/4 expected reagents found in inventory (0/5)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "project_found": project_found,
            "exp1_found": exp1_found,
            "exp2_found": exp2_found,
            "exp1_tasks_complete": sum([t_extract, t_quality, t_libprep, t_quant]),
            "exp2_tasks_complete": sum([t_trim, t_align, t_quant2]),
            "exp1_connections": sum([c1, c2, c3]),
            "exp2_connections": sum([c4, c5]),
            "protocol_steps": step_count,
            "inventory_found": inv_found,
            "inventory_columns": col_count,
            "items_found": items_matched
        }
    }
