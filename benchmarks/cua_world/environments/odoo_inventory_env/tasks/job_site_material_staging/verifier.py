#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_job_site_material_staging(traj, env_info, task_info):
    """
    Verify construction job site material staging and direct procurement.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_po_deltas = metadata.get('expected_po_deltas', {})
    expected_wh_remains = metadata.get('expected_wh_remains', {})
    requests = metadata.get('requests', {})
    pass_threshold = metadata.get('pass_threshold', 80)

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(metadata.get('result_file', '/tmp/job_site_staging_result.json'), local_path)
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    score = 0
    feedback = []
    
    # 1. Location Created (5 pts)
    if result.get('location_created'):
        score += 5
        feedback.append("PASS: 'Job Site - Riverfront' location created (+5)")
    else:
        feedback.append("FAIL: 'Job Site - Riverfront' location not found")

    # 2. Internal Transfer Completed (15 pts)
    if result.get('internal_transfers'):
        score += 15
        feedback.append("PASS: Internal transfer from WH/Stock to Job Site completed (+15)")
    else:
        feedback.append("FAIL: No validated internal transfer from WH/Stock to Job Site")

    # 3. PO Confirmed for Shortages (15 pts)
    po_score = 0
    products = result.get('products', {})
    po_matches = True
    for code, expected_qty in expected_po_deltas.items():
        actual_po = products.get(code, {}).get('po_qty', 0)
        if actual_po != expected_qty:
            po_matches = False
            feedback.append(f"FAIL: PO quantity for {code} is {actual_po}, expected {expected_qty}")
            
    if po_matches and sum(expected_po_deltas.values()) > 0:
        po_score = 15
        score += po_score
        feedback.append("PASS: PO confirmed for exact shortage quantities (+15)")
    elif sum([p.get('po_qty', 0) for p in products.values()]) > 0:
        po_score = 5
        score += po_score
        feedback.append("PARTIAL: PO created but quantities are incorrect (+5)")

    # 4. Direct-to-Site Receipt (15 pts)
    if result.get('direct_receipts'):
        score += 15
        feedback.append("PASS: Purchase receipt routed directly to Job Site (+15)")
    elif sum([p.get('po_qty', 0) for p in products.values()]) > 0:
        feedback.append("FAIL: PO was created but receipt was NOT routed directly to Job Site")

    # 5. Safety Hold Respected (15 pts)
    hazmat_code = 'CONST-HAZ-05'
    haz_site_qty = products.get(hazmat_code, {}).get('job_site_qty', 0)
    haz_po_qty = products.get(hazmat_code, {}).get('po_qty', 0)
    if haz_site_qty == 0 and haz_po_qty == 0:
        score += 15
        feedback.append("PASS: Safety hold respected, no Hazmat items transferred or purchased (+15)")
    else:
        feedback.append("FAIL: Safety hold ignored! Hazmat items were deployed or purchased.")

    # 6. Exact Final Quantities (25 pts - 5 pts per product)
    quantities_score = 0
    for code, expected_qty in requests.items():
        actual_site = products.get(code, {}).get('job_site_qty', 0)
        if actual_site == expected_qty:
            quantities_score += 5
            feedback.append(f"PASS: {code} final job site quantity is correct ({expected_qty}) (+5)")
        else:
            feedback.append(f"FAIL: {code} final job site quantity is {actual_site}, expected {expected_qty}")
    score += quantities_score

    # 7. Optimal Procurement (10 pts)
    # Ensure WH/Stock was depleted first
    wh_score = 10
    for code, expected_remains in expected_wh_remains.items():
        actual_wh = products.get(code, {}).get('wh_stock_qty', 0)
        if actual_wh > expected_remains:
            wh_score = 0
            feedback.append(f"FAIL: Optimal procurement failed. {code} was purchased when stock was available in WH/Stock.")
            break
    
    if wh_score > 0:
        score += wh_score
        feedback.append("PASS: Optimal procurement followed, existing stock was prioritized (+10)")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }