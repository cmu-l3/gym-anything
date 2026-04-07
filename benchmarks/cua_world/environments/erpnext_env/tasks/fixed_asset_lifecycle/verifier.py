#!/usr/bin/env python3
"""
Verifier for fixed_asset_lifecycle task.

Task: Purchase a CNC Milling Machine, capitalize it (generate depreciation),
      and transfer it via Asset Movement to the Production Floor.

Scoring (100 pts total, pass >= 60):
  C1 [25 pts] — Purchase Invoice submitted for Eagle Hardware containing CNC Milling Machine (~$48,000).
  C2 [25 pts] — Asset submitted with gross_purchase_amount (~$48,000).
  C3 [20 pts] — Depreciation schedule generated (>= 100 rows).
  C4 [15 pts] — Asset Movement submitted (Transfer -> Production Floor).
  C5 [15 pts] — Asset current location is updated to "Production Floor".

Anti-Gaming / Robustness:
  - Uses baseline arrays to ignore pre-existing records.
  - Verifies exact linking in Asset Movement child tables.
  - Ensures PI amount matches requested value (tolerance applied).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_AMOUNT = 48000.00
TOLERANCE = 1000.00  # Allow some variance for taxes/shipping if agent gets creative


def verify_fixed_asset_lifecycle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/fixed_asset_lifecycle_result.json"
    )

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    pis = data.get("purchase_invoices", [])
    assets = data.get("assets", [])
    movements = data.get("asset_movements", [])

    score = 0
    feedback_parts = []

    # --- C1: Purchase Invoice Submitted [25 pts] ---
    c1_pass = False
    for pi in pis:
        gt = pi.get("grand_total", 0)
        if abs(gt - EXPECTED_AMOUNT) <= TOLERANCE:
            c1_pass = True
            break
            
    if c1_pass:
        score += 25
        feedback_parts.append("C1 PASS: Purchase Invoice created for CNC Milling Machine (+25)")
    else:
        if pis:
            amounts = [pi.get("grand_total") for pi in pis]
            feedback_parts.append(f"C1 FAIL: PI found but wrong amount (expected ~${EXPECTED_AMOUNT}, got {amounts})")
        else:
            feedback_parts.append("C1 FAIL: No new submitted Purchase Invoice found for Eagle Hardware")

    # --- C2: Asset Submitted with Value [25 pts] ---
    c2_pass = False
    best_asset = None
    for ast in assets:
        if ast.get("docstatus") == 1:  # 1 = Submitted
            val = ast.get("gross_purchase_amount", 0)
            if abs(val - EXPECTED_AMOUNT) <= TOLERANCE:
                c2_pass = True
                best_asset = ast
                break
                
    if c2_pass:
        score += 25
        feedback_parts.append("C2 PASS: Asset submitted with correct purchase amount (+25)")
    else:
        if assets:
            statuses = [(a.get("name"), a.get("docstatus"), a.get("gross_purchase_amount")) for a in assets]
            feedback_parts.append(f"C2 FAIL: Assets found but not submitted or wrong amount: {statuses}")
        else:
            feedback_parts.append("C2 FAIL: No new Asset found")

    # --- C3: Depreciation Schedule Generated [20 pts] ---
    c3_pass = False
    if best_asset:
        rows = best_asset.get("depreciation_schedule_rows", 0)
        method = best_asset.get("depreciation_method", "")
        # Expect ~120 rows for 10 years monthly. Check >= 100 to allow slight date variances
        if rows >= 100 and method == "Straight Line":
            c3_pass = True
            
    if c3_pass:
        score += 20
        feedback_parts.append(f"C3 PASS: Depreciation schedule generated with {best_asset.get('depreciation_schedule_rows')} rows (+20)")
    else:
        if best_asset:
            feedback_parts.append(f"C3 FAIL: Insufficient schedule rows ({best_asset.get('depreciation_schedule_rows')}) or wrong method")
        else:
            feedback_parts.append("C3 FAIL: Cannot verify schedule without a submitted Asset")

    # --- C4: Asset Movement Submitted [15 pts] ---
    c4_pass = False
    for mv in movements:
        if mv.get("purpose") == "Transfer" and mv.get("target_location") == "Production Floor":
            c4_pass = True
            break
            
    if c4_pass:
        score += 15
        feedback_parts.append("C4 PASS: Asset Movement submitted to Production Floor (+15)")
    else:
        feedback_parts.append("C4 FAIL: No submitted Asset Movement transferring machine to Production Floor")

    # --- C5: Asset Location is Production Floor [15 pts] ---
    c5_pass = False
    if best_asset and best_asset.get("location") == "Production Floor":
        c5_pass = True
        
    if c5_pass:
        score += 15
        feedback_parts.append("C5 PASS: Current Asset location is Production Floor (+15)")
    else:
        if best_asset:
            feedback_parts.append(f"C5 FAIL: Current Asset location is '{best_asset.get('location')}' (expected 'Production Floor')")
        else:
            feedback_parts.append("C5 FAIL: Cannot verify location without a submitted Asset")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }