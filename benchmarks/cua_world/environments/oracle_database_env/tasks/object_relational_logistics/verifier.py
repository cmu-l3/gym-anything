#!/usr/bin/env python3
"""
Verifier for Object-Relational Logistics task.
Verifies the creation of UDTs, Nested Table, Data Loading, and Analytical View.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_object_relational_logistics(traj, env_info, task_info):
    """
    Verification logic:
    1. Types (T_MANIFEST_ITEM, T_MANIFEST_TAB) must exist and be valid.
    2. Table SHIPMENT_OBJECTS must exist with type T_MANIFEST_TAB for MANIFEST column.
    3. Nested table storage must be explicitly named STORED_MANIFEST_ITEMS.
    4. Row count must be 4 (consolidated from 10 CSV lines).
    5. Nested data for sample ID 1003 must match source CSV.
    6. View V_MANIFEST_WEIGHTS must exist and calculate correct totals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Types Check (15 pts)
    if result.get("types_exist") and result.get("types_valid"):
        score += 15
        feedback.append("Object types created correctly.")
    else:
        feedback.append("Types T_MANIFEST_ITEM or T_MANIFEST_TAB missing or invalid.")

    # 2. Table Structure (15 pts)
    if result.get("table_exists") and result.get("nested_column_type") == "T_MANIFEST_TAB":
        score += 15
        feedback.append("SHIPMENT_OBJECTS created with correct nested column type.")
    else:
        feedback.append("SHIPMENT_OBJECTS missing or MANIFEST column has wrong type.")

    # 3. Storage Clause (10 pts)
    storage_name = result.get("storage_table_name", "")
    if storage_name == "STORED_MANIFEST_ITEMS":
        score += 10
        feedback.append("Nested table storage named correctly.")
    else:
        feedback.append(f"Nested table storage name mismatch. Expected: STORED_MANIFEST_ITEMS, Found: {storage_name}")

    # 4. Data Loading - Consolidation (20 pts)
    # 4 Shipments total in CSV
    row_count = result.get("row_count", 0)
    if row_count == 4:
        score += 20
        feedback.append("Data loaded and consolidated correctly (4 rows).")
    elif row_count > 4:
        feedback.append(f"Data loading error: Rows not consolidated (found {row_count}, expected 4).")
    elif row_count == 0:
        feedback.append("Table is empty.")
    else:
        feedback.append(f"Incorrect row count: {row_count}.")

    # 5. Data Content Integrity (20 pts)
    # Check Shipment 1003: 3 items (LED Monitor, HDMI Cable, Wireless Mouse)
    sample_data = result.get("sample_nested_data", [])
    expected_1003_items = {"LED Monitor 27in", "HDMI Cable 2m", "Wireless Mouse"}
    found_items = set(item["name"] for item in sample_data)
    
    if expected_1003_items.issubset(found_items) and len(sample_data) == 3:
        score += 20
        feedback.append("Nested data for Shipment 1003 verified.")
    else:
        feedback.append(f"Nested data mismatch for Shipment 1003. Found: {found_items}")

    # 6. View Verification (20 pts)
    # Shipment 1003: 50*4.5 + 50*0.15 + 50*0.12 = 225 + 7.5 + 6.0 = 238.5 kg
    # Total items: 150
    if result.get("view_exists"):
        score += 5
        view_data_1003 = result.get("view_data", {}).get("1003")
        
        if view_data_1003:
            w_ok = abs(view_data_1003["total_weight"] - 238.5) < 0.1
            q_ok = view_data_1003["total_items"] == 150
            
            if w_ok and q_ok:
                score += 15
                feedback.append("View calculations correct.")
            else:
                feedback.append(f"View calculations incorrect for 1003. Got Weight: {view_data_1003['total_weight']}, Qty: {view_data_1003['total_items']}")
        else:
            feedback.append("Shipment 1003 not found in view.")
    else:
        feedback.append("View V_MANIFEST_WEIGHTS missing or invalid.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }