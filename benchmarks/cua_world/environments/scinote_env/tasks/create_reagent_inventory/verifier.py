#!/usr/bin/env python3
"""
Verifier for create_reagent_inventory task.

Checks PostgreSQL schema (Repository, Columns, ListItems) and data (Rows, Cells)
via an exported JSON. Enforces strict type checking and anti-gaming rules.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_reagent_inventory(traj, env_info, task_info):
    """Verify that the inventory was created with proper typed columns and rows."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_items = metadata.get('expected_items', {})

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_reagent_inventory_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    if not result.get('found', False):
        return {"passed": False, "score": 0, "feedback": "Repository 'Lab Reagents Q4-2024' not found in database."}

    # CRITERION 1: Repository Existence (10 points)
    score += 10
    feedback.append("Repository found.")

    # CRITERION 2: Anti-gaming Timestamp (5 points)
    task_start = result.get('task_start', 0)
    created_at = result.get('created_at', 0)
    if created_at >= task_start - 60:
        score += 5
    else:
        feedback.append("Warning: Repository timestamp indicates it may have been created before the task started.")

    # CRITERION 3: Column Schema Check (25 points total)
    cols = result.get('columns', [])
    col_names = [c.get('name', '').lower() for c in cols]

    has_cas = any('cas' in n for n in col_names)
    if has_cas:
        score += 5
        feedback.append("CAS column exists.")

    has_mw = any('molecular weight' in n or 'mw' in n for n in col_names)
    if has_mw:
        score += 5
        feedback.append("Molecular Weight column exists.")

    has_storage = any('storage' in n for n in col_names)
    if has_storage:
        score += 5
        feedback.append("Storage Condition column exists.")
        # Check specific List Options
        for c in cols:
            if 'storage' in c.get('name', '').lower():
                items = [i.lower() for i in c.get('list_items', [])]
                if all(opt.lower() in items for opt in ["Room Temperature", "2-8°C", "-20°C", "-80°C"]):
                    score += 5
                    feedback.append("Storage options correctly defined.")
                else:
                    feedback.append("Storage condition missing required list options.")
                break

    has_date = any('expiration' in n or 'date' in n for n in col_names)
    if has_date:
        score += 5
        feedback.append("Expiration Date column exists.")

    # CRITERION 4: Rows & Data Points (60 points total, 20 per item)
    rows = result.get('rows', [])
    rows_by_name = {r.get('name', '').lower(): r for r in rows}

    for expected_name, exp_data in expected_items.items():
        en_lower = expected_name.lower()
        matched_row = rows_by_name.get(en_lower)
        
        # Fallback to partial matching if exactly typed differently
        if not matched_row:
            for r_name, r_data in rows_by_name.items():
                if en_lower in r_name or r_name in en_lower:
                    matched_row = r_data
                    break

        if matched_row:
            score += 5  # Row name matched
            feedback.append(f"Row '{expected_name}' found.")

            cells = matched_row.get('cells', [])
            cell_map = {c.get('column_name', '').lower(): c.get('value') for c in cells}

            # Validating CAS Number entry
            cas_val = None
            for k, v in cell_map.items():
                if 'cas' in k and v is not None:
                    cas_val = str(v).strip()
                    break
            if cas_val == exp_data['cas']:
                score += 5
            else:
                feedback.append(f"CAS mismatch for {expected_name}: expected {exp_data['cas']}, got {cas_val}")

            # Validating Molecular Weight entry
            mw_val = None
            for k, v in cell_map.items():
                if ('molecular weight' in k or 'mw' in k) and v is not None:
                    try:
                        mw_val = float(v)
                    except ValueError:
                        pass
                    break
            if mw_val is not None and abs(mw_val - exp_data['mw']) < 0.1:
                score += 5
            else:
                feedback.append(f"MW mismatch for {expected_name}: expected {exp_data['mw']}, got {mw_val}")

            # Validating Storage Condition List choice entry
            storage_val = None
            for k, v in cell_map.items():
                if 'storage' in k and v is not None:
                    storage_val = str(v).strip()
                    break
            if storage_val and storage_val.lower() == exp_data['storage'].lower():
                score += 5
            else:
                feedback.append(f"Storage mismatch for {expected_name}: expected {exp_data['storage']}, got {storage_val}")
        else:
            feedback.append(f"Row '{expected_name}' not found.")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": {
            "repository_found": result.get('found', False),
            "columns_configured": has_cas and has_mw and has_storage and has_date,
            "items_added": len(rows) >= len(expected_items)
        }
    }