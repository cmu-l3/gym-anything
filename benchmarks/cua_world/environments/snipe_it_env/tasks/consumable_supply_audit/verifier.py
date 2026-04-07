#!/usr/bin/env python3
"""
Verifier for consumable_supply_audit task.

Checks database state exported by export_result.sh.
Criteria:
- C1 (15 pts): Ink Cartridge created with correct specs
- C2 (15 pts): Ethernet Cable created with correct specs
- C3 (15 pts): USB-C Adapter created with correct specs
- C4 (12 pts): Ink checkout to jsmith (2 units)
- C5 (12 pts): Cable checkout to ajohnson (3 units)
- C6 (10 pts): Flash Drive Min QTY updated to 20
- C7 (10 pts): Batteries Min QTY updated to 30
- C8 (11 pts): No unintended changes (count matches, existing not mangled)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_consumable_supply_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_ink = metadata.get('expected_ink', {})
    expected_cable = metadata.get('expected_cable', {})
    expected_adapter = metadata.get('expected_adapter', {})

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

    score = 0
    feedback_parts = []

    # Anti-gaming: Ensure work was actually done during task time
    if result.get("created_after_start", 0) == 0 and result.get("final_count", 0) > result.get("initial_count", 0):
        # We expected new items to be created. If they were pre-seeded (timestamp failure), flag it.
        pass  # We still check DB fields, but this is a soft signal.

    # ---------------------------------------------------------------
    # C1: Ink Cartridge (15 pts)
    # ---------------------------------------------------------------
    ink = result.get("ink", {})
    if ink.get("found"):
        c1_score = 0
        qty = float(ink.get("qty", 0))
        # Handle qty representing before or after checkout
        if qty == expected_ink.get("qty") or qty == (expected_ink.get("qty") - 2):
            c1_score += 3
        if float(ink.get("min_amt", 0)) == expected_ink.get("min_amt"):
            c1_score += 3
        if math.isclose(float(ink.get("cost", 0)), expected_ink.get("cost"), abs_tol=0.1):
            c1_score += 3
        if ink.get("model") == expected_ink.get("model"):
            c1_score += 3
        if ink.get("order") == expected_ink.get("order"):
            c1_score += 3
        
        score += c1_score
        feedback_parts.append(f"C1: Ink Cartridge (+{c1_score}/15)")
    else:
        feedback_parts.append("C1: Ink Cartridge not found (+0/15)")

    # ---------------------------------------------------------------
    # C2: Ethernet Cable (15 pts)
    # ---------------------------------------------------------------
    cable = result.get("cable", {})
    if cable.get("found"):
        c2_score = 0
        qty = float(cable.get("qty", 0))
        if qty == expected_cable.get("qty") or qty == (expected_cable.get("qty") - 3):
            c2_score += 3
        if float(cable.get("min_amt", 0)) == expected_cable.get("min_amt"):
            c2_score += 3
        if math.isclose(float(cable.get("cost", 0)), expected_cable.get("cost"), abs_tol=0.1):
            c2_score += 3
        if cable.get("model") == expected_cable.get("model"):
            c2_score += 3
        if cable.get("order") == expected_cable.get("order"):
            c2_score += 3
            
        score += c2_score
        feedback_parts.append(f"C2: Ethernet Cable (+{c2_score}/15)")
    else:
        feedback_parts.append("C2: Ethernet Cable not found (+0/15)")

    # ---------------------------------------------------------------
    # C3: USB-C Adapter (15 pts)
    # ---------------------------------------------------------------
    adapter = result.get("adapter", {})
    if adapter.get("found"):
        c3_score = 0
        if float(adapter.get("qty", 0)) == expected_adapter.get("qty"):
            c3_score += 3
        if float(adapter.get("min_amt", 0)) == expected_adapter.get("min_amt"):
            c3_score += 3
        if math.isclose(float(adapter.get("cost", 0)), expected_adapter.get("cost"), abs_tol=0.1):
            c3_score += 3
        if adapter.get("model") == expected_adapter.get("model"):
            c3_score += 3
        if adapter.get("order") == expected_adapter.get("order"):
            c3_score += 3
            
        score += c3_score
        feedback_parts.append(f"C3: USB-C Adapter (+{c3_score}/15)")
    else:
        feedback_parts.append("C3: USB-C Adapter not found (+0/15)")

    # ---------------------------------------------------------------
    # C4: Ink Checkout to jsmith (12 pts)
    # ---------------------------------------------------------------
    ink_checkouts = result.get("ink_checkouts_jsmith", 0)
    ink_qty = float(ink.get("qty", 0)) if ink.get("found") else 0
    
    if ink_checkouts >= 2 or ink_qty == (expected_ink.get("qty", 50) - 2):
        score += 12
        feedback_parts.append("C4: Ink checked out to jsmith (+12/12)")
    elif ink_checkouts == 1 or ink_qty == (expected_ink.get("qty", 50) - 1):
        score += 6
        feedback_parts.append("C4: Partial ink checkout (+6/12)")
    else:
        feedback_parts.append("C4: Ink not checked out correctly (+0/12)")

    # ---------------------------------------------------------------
    # C5: Cable Checkout to ajohnson (12 pts)
    # ---------------------------------------------------------------
    cable_checkouts = result.get("cable_checkouts_ajohnson", 0)
    cable_qty = float(cable.get("qty", 0)) if cable.get("found") else 0
    
    if cable_checkouts >= 3 or cable_qty == (expected_cable.get("qty", 200) - 3):
        score += 12
        feedback_parts.append("C5: Cable checked out to ajohnson (+12/12)")
    elif cable_checkouts in [1, 2]:
        score += 6
        feedback_parts.append("C5: Partial cable checkout (+6/12)")
    else:
        feedback_parts.append("C5: Cable not checked out correctly (+0/12)")

    # ---------------------------------------------------------------
    # C6: Flash Drive Min QTY (10 pts)
    # ---------------------------------------------------------------
    flash = result.get("flash_drive", {})
    if float(flash.get("min_amt", 0)) == 20.0:
        score += 10
        feedback_parts.append("C6: Flash Drive min updated (+10/10)")
    else:
        feedback_parts.append(f"C6: Flash Drive min is {flash.get('min_amt')}, expected 20 (+0/10)")

    # ---------------------------------------------------------------
    # C7: Batteries Min QTY (10 pts)
    # ---------------------------------------------------------------
    batt = result.get("batteries", {})
    if float(batt.get("min_amt", 0)) == 30.0:
        score += 10
        feedback_parts.append("C7: Batteries min updated (+10/10)")
    else:
        feedback_parts.append(f"C7: Batteries min is {batt.get('min_amt')}, expected 30 (+0/10)")

    # ---------------------------------------------------------------
    # C8: Unintended changes (11 pts)
    # ---------------------------------------------------------------
    c8_score = 0
    initial_count = result.get("initial_count", 0)
    final_count = result.get("final_count", 0)
    
    if final_count == initial_count + 3:
        c8_score += 5  # No extra consumables created
        
    # Check that existing items were not renamed
    if "Flash Drive" in flash.get("name", "") and "Batteries" in batt.get("name", ""):
        c8_score += 6
        
    score += c8_score
    feedback_parts.append(f"C8: Unintended changes check (+{c8_score}/11)")

    passed = score >= 60 and (ink.get("found") or cable.get("found") or adapter.get("found"))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }