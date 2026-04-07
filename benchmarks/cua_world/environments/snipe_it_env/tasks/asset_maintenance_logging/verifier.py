#!/usr/bin/env python3
"""
Verifier for asset_maintenance_logging task.

This verifier checks the exported database state and assigns points based on the 
correctness of each field for each of the 4 requested maintenance records.

Total points: 100
Pass threshold: 60
Each of the 4 records is worth 25 points.
(4 pts for type, 4 pts for start date, 4 pts for completion date, 
 4 pts for cost, 4 pts for supplier, 5 pts for accurate notes).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def evaluate_record(record, expected_type, expected_start, expected_completion, expected_cost, expected_supplier, expected_note_kw):
    """Evaluates a single parsed record against expected values and returns points."""
    if not record or not record.get('found'):
        return 0, [f"Record not found."]
        
    score = 0
    feedback = []

    # 1. Maintenance Type (4 pts)
    actual_type = record.get('type', '')
    if expected_type.lower() in actual_type.lower():
        score += 4
        feedback.append(f"Type OK")
    else:
        feedback.append(f"Type mismatch (Expected {expected_type}, got {actual_type})")

    # 2. Start Date (4 pts)
    actual_start = record.get('start_date', '')
    if expected_start in actual_start:
        score += 4
        feedback.append(f"Start OK")
    else:
        feedback.append(f"Start mismatch (Expected {expected_start}, got {actual_start})")

    # 3. Completion Date (4 pts)
    actual_comp = record.get('completion_date', '')
    if expected_completion is None:
        if not actual_comp or actual_comp.upper() == 'NULL' or '0000-00-00' in actual_comp:
            score += 4
            feedback.append("Completion OK (Blank)")
        else:
            feedback.append(f"Completion mismatch (Expected Blank, got {actual_comp})")
    else:
        if expected_completion in actual_comp:
            score += 4
            feedback.append(f"Completion OK")
        else:
            feedback.append(f"Completion mismatch (Expected {expected_completion}, got {actual_comp})")

    # 4. Cost (4 pts)
    actual_cost_str = str(record.get('cost', '0')).replace(',', '').replace('$', '')
    try:
        actual_cost_val = float(actual_cost_str)
    except ValueError:
        actual_cost_val = -1.0
        
    if abs(actual_cost_val - expected_cost) < 0.1:
        score += 4
        feedback.append(f"Cost OK")
    else:
        feedback.append(f"Cost mismatch (Expected {expected_cost}, got {actual_cost_str})")

    # 5. Supplier (4 pts)
    actual_supplier = record.get('supplier', '')
    if expected_supplier.lower() in actual_supplier.lower():
        score += 4
        feedback.append(f"Supplier OK")
    else:
        feedback.append(f"Supplier mismatch (Expected {expected_supplier}, got {actual_supplier})")

    # 6. Notes keyword (5 pts)
    actual_notes = record.get('notes', '')
    if expected_note_kw.lower() in actual_notes.lower():
        score += 5
        feedback.append(f"Notes OK")
    else:
        feedback.append(f"Notes mismatch (Missing keyword '{expected_note_kw}')")

    return score, feedback

def verify_asset_maintenance_logging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    total_score = 0
    feedback_lines = []
    records = result.get('records', {})

    # Check anti-gaming
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    if final_count <= initial_count:
        feedback_lines.append(f"WARNING: No new maintenance records were created (initial={initial_count}, final={final_count}).")

    # Evaluate Record 1: ASSET-0001
    r1_score, r1_fb = evaluate_record(
        records.get('asset_0001', {}), 
        expected_type="Maintenance", expected_start="2025-02-15", 
        expected_completion="2025-02-18", expected_cost=450.0, 
        expected_supplier="Acme Corp", expected_note_kw="cooling fans"
    )
    total_score += r1_score
    feedback_lines.append(f"ASSET-0001 [{r1_score}/25 pts]: " + ", ".join(r1_fb))

    # Evaluate Record 2: ASSET-0002
    r2_score, r2_fb = evaluate_record(
        records.get('asset_0002', {}), 
        expected_type="Repair", expected_start="2025-02-20", 
        expected_completion="2025-02-22", expected_cost=275.0, 
        expected_supplier="Dell", expected_note_kw="bad sectors"
    )
    total_score += r2_score
    feedback_lines.append(f"ASSET-0002 [{r2_score}/25 pts]: " + ", ".join(r2_fb))

    # Evaluate Record 3: ASSET-0003
    r3_score, r3_fb = evaluate_record(
        records.get('asset_0003', {}), 
        expected_type="Upgrade", expected_start="2025-03-01", 
        expected_completion="2025-03-01", expected_cost=180.0, 
        expected_supplier="Lenovo", expected_note_kw="16GB to 32GB"
    )
    total_score += r3_score
    feedback_lines.append(f"ASSET-0003 [{r3_score}/25 pts]: " + ", ".join(r3_fb))

    # Evaluate Record 4: ASSET-0005
    r4_score, r4_fb = evaluate_record(
        records.get('asset_0005', {}), 
        expected_type="Maintenance", expected_start="2025-02-25", 
        expected_completion=None, expected_cost=320.0, 
        expected_supplier="HP", expected_note_kw="fuser replacement"
    )
    total_score += r4_score
    feedback_lines.append(f"ASSET-0005 [{r4_score}/25 pts]: " + ", ".join(r4_fb))

    passed = total_score >= 60

    return {
        "passed": passed,
        "score": total_score,
        "feedback": "\n".join(feedback_lines)
    }