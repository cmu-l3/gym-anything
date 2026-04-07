#!/usr/bin/env python3
"""Verifier for setup_forced_degradation_study task.

Scoring: 100 points total, pass at 60.

Breakdown:
  - Project found:               5 pts
  - Experiment found:             5 pts
  - 5 tasks found (2 each):     10 pts
  - 6 connections (5 each):     30 pts  (highest weight — hardest operation)
  - Protocol >= 6 steps:        12 pts  (partial 6 for >= 3)
  - Inventory found:             3 pts
  - Inventory columns >= 2:      5 pts
  - 3 inventory items:           9 pts  (3 each)
  - Inventory-to-task assign:   10 pts  (5 per assigned item, up to 2)
  - Smart annotation in result:  8 pts
  - Result text exists:          3 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_forced_degradation_study(traj, env_info, task_info):
    """Verify forced degradation study documentation was created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/forced_degradation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- 1. Project (5 pts) ----
    project_found = result.get('project_found', False)
    if project_found:
        score += 5
        feedback_parts.append("Project found")
    else:
        feedback_parts.append("Project NOT found")
        # Early exit if project missing
        return {
            "passed": False,
            "score": 0,
            "feedback": "Project not found — cannot verify further",
            "subscores": {"project_found": False}
        }
    subscores['project_found'] = project_found

    # ---- 2. Experiment (5 pts) ----
    exp_found = result.get('experiment_found', False)
    if exp_found:
        score += 5
        feedback_parts.append("Experiment found")
    else:
        feedback_parts.append("Experiment NOT found")
    subscores['experiment_found'] = exp_found

    # ---- 3. Tasks (10 pts: 2 each) ----
    task_ids = {
        'stock': result.get('task_stock_id', ''),
        'acid': result.get('task_acid_id', ''),
        'base': result.get('task_base_id', ''),
        'oxi': result.get('task_oxi_id', ''),
        'hplc': result.get('task_hplc_id', ''),
    }
    tasks_found = 0
    for key, tid in task_ids.items():
        found = bool(tid and str(tid).strip())
        subscores[f'task_{key}_found'] = found
        if found:
            score += 2
            tasks_found += 1
    feedback_parts.append(f"Tasks found: {tasks_found}/5")

    # ---- 4. Connections (30 pts: 5 each) ----
    conn_keys = [
        'conn_stock_to_acid', 'conn_stock_to_base', 'conn_stock_to_oxi',
        'conn_acid_to_hplc', 'conn_base_to_hplc', 'conn_oxi_to_hplc',
    ]
    conns_found = 0
    for ck in conn_keys:
        if result.get(ck, False):
            score += 5
            conns_found += 1
        subscores[ck] = result.get(ck, False)
    feedback_parts.append(f"Connections: {conns_found}/6")

    # ---- 5. Protocol steps (12 pts) ----
    step_count = int(result.get('protocol_step_count', 0))
    if step_count >= 6:
        score += 12
        feedback_parts.append(f"Protocol: {step_count} steps (full credit)")
    elif step_count >= 3:
        score += 6
        feedback_parts.append(f"Protocol: {step_count} steps (partial credit)")
    else:
        feedback_parts.append(f"Protocol: {step_count} steps (insufficient)")
    subscores['protocol_step_count'] = step_count

    # ---- 6. Inventory (3 pts found + 5 pts columns + 9 pts items) ----
    repo_found = result.get('inventory_found', False)
    if repo_found:
        score += 3
        feedback_parts.append("Inventory found")
    else:
        feedback_parts.append("Inventory NOT found")
    subscores['inventory_found'] = repo_found

    col_count = int(result.get('inventory_column_count', 0))
    if col_count >= 2:
        score += 5
    subscores['inventory_column_count'] = col_count

    # Check inventory items by name keyword matching
    items = result.get('inventory_items', [])
    item_keywords = ['ibuprofen', 'hcl', 'naoh']
    items_matched = 0
    for kw in item_keywords:
        if any(kw in item.lower() for item in items):
            score += 3
            items_matched += 1
    feedback_parts.append(f"Inventory items: {items_matched}/3")
    subscores['inventory_items_matched'] = items_matched

    # ---- 7. Inventory-to-task assignments (10 pts: 5 per item, up to 2) ----
    assigned_items = result.get('assigned_items', [])
    assigned_count = min(int(result.get('assigned_count', 0)), 2)
    assign_score = assigned_count * 5
    score += assign_score
    feedback_parts.append(f"Inventory assignments: {assigned_count}/2")
    subscores['assigned_count'] = int(result.get('assigned_count', 0))
    subscores['assigned_items'] = assigned_items

    # ---- 8. Result text on HPLC task (3 pts) + Smart annotation (8 pts) ----
    has_result = result.get('has_result_text', False)
    if has_result:
        score += 3
        feedback_parts.append("Result text found on HPLC task")
    else:
        feedback_parts.append("No result text on HPLC task")
    subscores['has_result_text'] = has_result

    rich_text = result.get('rich_text', '')
    # SciNote stores smart annotations in two possible formats:
    # 1. Modern ActionText: <action-text-attachment sgid=...> tags
    # 2. Legacy/atwho: [#ItemName~rep_item~ID] inline markers
    smart_annotation_indicators = [
        "<action-text-attachment", "sgid=", "data-mention", "repository_row",
        "[#", "~rep_item~",
    ]
    keyword = 'ibuprofen'
    has_smart_link = False

    if has_result and keyword in rich_text.lower():
        has_smart_link = any(ind in rich_text for ind in smart_annotation_indicators)
        if has_smart_link:
            score += 8
            feedback_parts.append("Smart annotation verified")
        else:
            feedback_parts.append("Text mentions Ibuprofen but no smart annotation markup found")
    else:
        feedback_parts.append("Smart annotation not found in result text")
    subscores['smart_annotation_found'] = has_smart_link

    # ---- Final scoring ----
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
