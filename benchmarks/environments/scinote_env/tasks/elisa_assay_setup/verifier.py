#!/usr/bin/env python3
"""Verifier for elisa_assay_setup task."""

import json
import tempfile
import os


def verify_elisa_assay_setup(traj, env_info, task_info):
    """Verify ELISA assay ELN setup: experiment, tasks, connections, protocol, expanded inventory."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/elisa_assay_setup_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Criterion 1 (15 pts): Experiment 'Antibody Pair Optimization' created ---
    exp_found = result.get('experiment_found', False)
    if exp_found:
        score += 15
        feedback.append("Experiment 'Antibody Pair Optimization' found (15/15)")
    else:
        feedback.append("Experiment 'Antibody Pair Optimization' NOT found (0/15)")

    # --- Criterion 2 (20 pts): All 4 tasks exist ---
    all_tasks_lower = [t.lower() for t in result.get('all_tasks', [])]
    has_coat = any('plate' in t and 'coat' in t for t in all_tasks_lower)
    has_dilut = any('sample' in t and 'dilut' in t for t in all_tasks_lower)
    has_primary = any('primary' in t and 'antibody' in t for t in all_tasks_lower)
    has_signal = any('signal' in t and 'detect' in t for t in all_tasks_lower)

    task_pts = sum([has_coat, has_dilut, has_primary, has_signal]) * 5
    score += task_pts
    if has_coat:
        feedback.append("Task 'Plate Coating' found")
    else:
        feedback.append("Task 'Plate Coating' NOT found")
    if has_dilut:
        feedback.append("Task 'Sample Dilution' found")
    else:
        feedback.append("Task 'Sample Dilution' NOT found")
    if has_primary:
        feedback.append("Task 'Primary Antibody Incubation' found")
    else:
        feedback.append("Task 'Primary Antibody Incubation' NOT found")
    if has_signal:
        feedback.append("Task 'Signal Detection' found")
    else:
        feedback.append("Task 'Signal Detection' NOT found")

    # --- Criterion 3 (15 pts): Connections in correct order ---
    conn1 = result.get('conn_coat_to_dilut', False)
    conn2 = result.get('conn_dilut_to_primary', False)
    conn3 = result.get('conn_primary_to_signal', False)

    conn_pts = sum([conn1, conn2, conn3]) * 5
    score += conn_pts
    if conn1:
        feedback.append("Connection 'Plate Coating' → 'Sample Dilution' found")
    else:
        feedback.append("Connection 'Plate Coating' → 'Sample Dilution' NOT found")
    if conn2:
        feedback.append("Connection 'Sample Dilution' → 'Primary Antibody Incubation' found")
    else:
        feedback.append("Connection 'Sample Dilution' → 'Primary Antibody Incubation' NOT found")
    if conn3:
        feedback.append("Connection 'Primary Antibody Incubation' → 'Signal Detection' found")
    else:
        feedback.append("Connection 'Primary Antibody Incubation' → 'Signal Detection' NOT found")

    # --- Criterion 4 (10 pts): ≥5 steps in Plate Coating protocol ---
    step_count = int(result.get('plate_coating_step_count', 0))
    if step_count >= 5:
        score += 10
        feedback.append(f"Plate Coating protocol has {step_count} steps (≥5) (10/10)")
    elif step_count >= 3:
        score += 5
        feedback.append(f"Plate Coating protocol has {step_count} steps (partial, need ≥5) (5/10)")
    else:
        feedback.append(f"Plate Coating protocol has {step_count} steps (need ≥5) (0/10)")

    # --- Criterion 5 (10 pts): 2 new columns added to inventory ---
    has_volume = result.get('has_volume_column', False)
    has_storage = result.get('has_storage_column', False)
    col_pts = (5 if has_volume else 0) + (5 if has_storage else 0)
    score += col_pts
    feedback.append(f"New column 'Volume (mL)': {'found' if has_volume else 'NOT found'}")
    feedback.append(f"New column 'Storage Temperature': {'found' if has_storage else 'NOT found'}")

    # --- Criterion 6 (30 pts): 3 items with correct catalog numbers ---
    items = result.get('inventory_items', [])
    item_lower = {it.get('name', '').lower(): it for it in items}

    expected = [
        ('il-6 capture antibody', 'MAB206'),
        ('il-6 detection antibody', 'BAF206'),
        ('streptavidin-hrp', 'DY998'),
    ]
    items_found = 0
    catalogs_ok = 0
    for kw, catalog in expected:
        match = next((n for n in item_lower if kw in n or n in kw), None)
        if match:
            items_found += 1
            score += 5
            actual_cat = item_lower[match].get('catalog_number', '').strip()
            if actual_cat == catalog:
                catalogs_ok += 1
                score += 5
                feedback.append(f"Item '{kw}' found with correct catalog '{catalog}'")
            else:
                feedback.append(f"Item '{kw}' found but catalog '{actual_cat}' != '{catalog}'")
        else:
            feedback.append(f"Item matching '{kw}' NOT found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "experiment_found": exp_found,
            "tasks_found": sum([has_coat, has_dilut, has_primary, has_signal]),
            "connections_correct": sum([conn1, conn2, conn3]),
            "protocol_steps": step_count,
            "new_columns": col_pts // 5,
            "items_found": items_found,
            "catalogs_correct": catalogs_ok
        }
    }
