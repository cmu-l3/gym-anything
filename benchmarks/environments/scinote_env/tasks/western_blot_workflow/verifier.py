#!/usr/bin/env python3
"""Verifier for western_blot_workflow task."""

import json
import tempfile
import os


def verify_western_blot_workflow(traj, env_info, task_info):
    """Verify western blot workflow completion: new tasks, connections, protocol, inventory."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/western_blot_workflow_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    all_tasks = [t.lower() for t in result.get('all_task_names', [])]
    task_count = int(result.get('task_count', 0))

    # --- Criterion 1 (15 pts): Both new tasks exist ---
    has_sdspage = any('sds' in t and 'page' in t for t in all_tasks)
    has_transfer = any('membrane' in t and 'transfer' in t for t in all_tasks)

    if has_sdspage:
        score += 7
        feedback.append("Task 'SDS-PAGE' found (7/7)")
    else:
        feedback.append("Task 'SDS-PAGE' NOT found (0/7)")

    if has_transfer:
        score += 8
        feedback.append("Task 'Membrane Transfer' found (8/8)")
    else:
        feedback.append("Task 'Membrane Transfer' NOT found (0/8)")

    # --- Criterion 2 (15 pts): Total task count is 4 ---
    if task_count >= 4:
        score += 15
        feedback.append(f"Experiment has {task_count} tasks (≥4 required) (15/15)")
    elif task_count == 3:
        score += 7
        feedback.append(f"Experiment has {task_count} tasks (need 4) (7/15)")
    else:
        feedback.append(f"Experiment has only {task_count} tasks (need 4) (0/15)")

    # --- Criterion 3 (15 pts): Connection Sample Prep → SDS-PAGE ---
    conn1 = result.get('conn_sample_to_sdspage', False)
    if conn1:
        score += 15
        feedback.append("Connection 'Sample Preparation' → 'SDS-PAGE' found (15/15)")
    else:
        feedback.append("Connection 'Sample Preparation' → 'SDS-PAGE' NOT found (0/15)")

    # --- Criterion 4 (15 pts): Connection SDS-PAGE → Membrane Transfer ---
    conn2 = result.get('conn_sdspage_to_transfer', False)
    if conn2:
        score += 15
        feedback.append("Connection 'SDS-PAGE' → 'Membrane Transfer' found (15/15)")
    else:
        feedback.append("Connection 'SDS-PAGE' → 'Membrane Transfer' NOT found (0/15)")

    # --- Criterion 5 (10 pts): Connection Membrane Transfer → Detection ---
    conn3 = result.get('conn_transfer_to_detect', False)
    if conn3:
        score += 10
        feedback.append("Connection 'Membrane Transfer' → 'Detection and Imaging' found (10/10)")
    else:
        feedback.append("Connection 'Membrane Transfer' → 'Detection and Imaging' NOT found (0/10)")

    # --- Criterion 6 (10 pts): ≥5 steps in Membrane Transfer protocol ---
    step_count = int(result.get('membrane_transfer_step_count', 0))
    if step_count >= 5:
        score += 10
        feedback.append(f"Membrane Transfer protocol has {step_count} steps (≥5 required) (10/10)")
    elif step_count >= 3:
        score += 5
        feedback.append(f"Membrane Transfer protocol has {step_count} steps (partial, need ≥5) (5/10)")
    else:
        feedback.append(f"Membrane Transfer protocol has {step_count} steps (need ≥5) (0/10)")

    # --- Criterion 7 (10 pts): Inventory 'Western Blot Reagents' with 3 columns ---
    inv_found = result.get('inventory_found', False)
    col_count = int(result.get('inventory_column_count', 0))
    if inv_found and col_count >= 3:
        score += 10
        feedback.append(f"Inventory 'Western Blot Reagents' found with {col_count} columns (10/10)")
    elif inv_found:
        score += 5
        feedback.append(f"Inventory found but only {col_count} columns (need 3) (5/10)")
    else:
        feedback.append("Inventory 'Western Blot Reagents' NOT found (0/10)")

    # --- Criterion 8 (up to 10 pts): 3 correct items with catalog numbers ---
    items = result.get('inventory_items', [])
    item_names_lower = [it.get('name', '').lower() for it in items]
    item_map = {it.get('name', '').lower(): it for it in items}

    expected = [
        ('pvdf membrane', 'IPVH00010'),
        ('non-fat milk', '1706404'),
        ('anti-beta-actin', 'A5441'),
    ]
    items_found = 0
    catalogs_ok = 0
    for kw, catalog in expected:
        match = next((n for n in item_names_lower if kw in n), None)
        if match:
            items_found += 1
            actual_cat = item_map[match].get('catalog_number', '').strip()
            if actual_cat == catalog:
                catalogs_ok += 1

    item_score = items_found * 2 + catalogs_ok * 1
    # Cap at 10 but scale: 3 items = 6, 3 catalogs = 3 → 9 out of 10
    item_score = min(item_score * 10 // 9, 10) if (items_found + catalogs_ok) > 0 else 0
    score += item_score
    feedback.append(f"Inventory items: {items_found}/3 found, {catalogs_ok}/3 catalog numbers correct ({item_score}/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "sdspage_task": has_sdspage,
            "transfer_task": has_transfer,
            "task_count": task_count,
            "conn1": conn1,
            "conn2": conn2,
            "conn3": conn3,
            "protocol_steps": step_count,
            "inventory_found": inv_found,
            "items_found": items_found,
            "catalogs_correct": catalogs_ok
        }
    }
