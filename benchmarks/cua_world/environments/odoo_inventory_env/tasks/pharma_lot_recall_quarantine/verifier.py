#!/usr/bin/env python3
"""
Verifier for pharma_lot_recall_quarantine task.

Scoring (100 pts total, pass threshold: 75):
   5 pts  - Quarantine location exists as child of WH/Stock
   8 pts  - AMX-2024-041 in quarantine, qty=500
   8 pts  - AMX-2024-089 in quarantine, qty=200
   8 pts  - IBU-2024-033 in quarantine, qty=800
   8 pts  - CET-2024-071 in quarantine, qty=500
  10 pts  - IBU-2024-112 NOT quarantined (trap: MedSource but outside recall window)
   8 pts  - Non-MedSource lots NOT quarantined (AMX-2024-067, CET-2024-015)
   5 pts  - PO to SafePharm Industries exists (confirmed)
   8 pts  - PO has Amoxicillin qty ~700
   8 pts  - PO has Ibuprofen qty ~800
   8 pts  - PO has Cetirizine qty ~500
   5 pts  - PO is confirmed (state='purchase')
  5.5 pts - Anti-gaming: Metformin lots untouched
  5.5 pts - Anti-gaming: Omeprazole lots untouched
         - Anti-gaming violation caps score at 50

Stub verifier — full verification is done via external VLM evaluation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected state constants (not exposed in task description)
AFFECTED_LOTS = {
    'AMX-2024-041': {'product_code': 'PHARMA-AMX', 'qty': 500},
    'AMX-2024-089': {'product_code': 'PHARMA-AMX', 'qty': 200},
    'IBU-2024-033': {'product_code': 'PHARMA-IBU', 'qty': 800},
    'CET-2024-071': {'product_code': 'PHARMA-CET', 'qty': 500},
}

TRAP_LOT = {
    'IBU-2024-112': {'product_code': 'PHARMA-IBU', 'qty': 600},
}

NON_MEDSOURCE_LOTS = {
    'AMX-2024-067': {'product_code': 'PHARMA-AMX', 'qty': 300},
    'CET-2024-015': {'product_code': 'PHARMA-CET', 'qty': 1000},
}

CONTROL_LOTS = {
    'MET-2024-022': {'product_code': 'PHARMA-MET', 'qty': 750},
    'MET-2024-045': {'product_code': 'PHARMA-MET', 'qty': 600},
    'OMP-2024-019': {'product_code': 'PHARMA-OMP', 'qty': 400},
}

EXPECTED_PO_QTY = {
    'PHARMA-AMX': 700,
    'PHARMA-IBU': 800,
    'PHARMA-CET': 500,
}

PASS_THRESHOLD = 75


def verify_pharma_lot_recall(traj, env_info, task_info):
    """Verify pharmaceutical lot recall quarantine and replenishment."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/pharma_recall_result.json')
    pass_threshold = metadata.get('pass_threshold', PASS_THRESHOLD)

    # Load exported result JSON
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False, "score": 0,
            "feedback": "Export file not found: {}".format(e),
        }

    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, "score": 0,
            "feedback": "Could not parse export result: {}".format(e),
        }
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    score = 0
    feedback = []
    subscores = {}

    lots = result.get('lots', {})
    quarantine = result.get('quarantine', {})
    po_data = result.get('purchase_orders', {})

    # ------------------------------------------------------------------
    # Criterion 1 (5 pts): Quarantine location exists as child of WH/Stock
    # ------------------------------------------------------------------
    if quarantine.get('found') and quarantine.get('is_child_of_wh_stock'):
        score += 5
        subscores['quarantine_location'] = True
        feedback.append("PASS: Quarantine location created under WH/Stock (+5)")
    elif quarantine.get('found'):
        score += 2
        subscores['quarantine_location'] = 'partial'
        feedback.append("PARTIAL: Quarantine location exists but not under WH/Stock (+2)")
    else:
        subscores['quarantine_location'] = False
        feedback.append("FAIL: No quarantine location found")

    # ------------------------------------------------------------------
    # Criterion 2 (32 pts): Affected lots correctly quarantined (8 pts each)
    # ------------------------------------------------------------------
    for lot_name, spec in AFFECTED_LOTS.items():
        lot_data = lots.get(lot_name, {})
        q_qty = lot_data.get('quarantine_qty', 0)
        expected = spec['qty']

        if abs(q_qty - expected) < 0.01:
            score += 8
            subscores['quarantine_{}'.format(lot_name)] = True
            feedback.append("PASS: {} quarantined with qty={} (+8)".format(lot_name, expected))
        elif q_qty > 0:
            score += 4
            subscores['quarantine_{}'.format(lot_name)] = 'partial'
            feedback.append("PARTIAL: {} in quarantine but qty={} (expected {}) (+4)".format(
                lot_name, q_qty, expected))
        else:
            subscores['quarantine_{}'.format(lot_name)] = False
            feedback.append("FAIL: {} not quarantined (quarantine_qty={})".format(lot_name, q_qty))

    # ------------------------------------------------------------------
    # Criterion 3 (10 pts): Trap lot IBU-2024-112 NOT quarantined
    # ------------------------------------------------------------------
    trap_name = 'IBU-2024-112'
    trap_data = lots.get(trap_name, {})
    trap_q_qty = trap_data.get('quarantine_qty', 0)
    trap_wh_qty = trap_data.get('wh_stock_qty', 0)

    if trap_q_qty == 0 and abs(trap_wh_qty - 600) < 0.01:
        score += 10
        subscores['trap_lot_correct'] = True
        feedback.append("PASS: Trap lot {} correctly left in WH/Stock (+10)".format(trap_name))
    elif trap_q_qty == 0:
        score += 5
        subscores['trap_lot_correct'] = 'partial'
        feedback.append("PARTIAL: {} not quarantined but WH/Stock qty={} (expected 600) (+5)".format(
            trap_name, trap_wh_qty))
    else:
        subscores['trap_lot_correct'] = False
        feedback.append("FAIL: Trap lot {} was incorrectly quarantined (qty={})".format(
            trap_name, trap_q_qty))

    # ------------------------------------------------------------------
    # Criterion 4 (8 pts): Non-MedSource lots NOT quarantined
    # ------------------------------------------------------------------
    non_ms_ok = True
    for lot_name, spec in NON_MEDSOURCE_LOTS.items():
        lot_data = lots.get(lot_name, {})
        q_qty = lot_data.get('quarantine_qty', 0)
        if q_qty > 0:
            non_ms_ok = False
            feedback.append("FAIL: Non-MedSource lot {} incorrectly quarantined".format(lot_name))

    if non_ms_ok:
        score += 8
        subscores['non_medsource_correct'] = True
        feedback.append("PASS: Non-MedSource lots correctly left untouched (+8)")
    else:
        subscores['non_medsource_correct'] = False

    # ------------------------------------------------------------------
    # Criterion 5 (5 pts): PO to SafePharm exists
    # ------------------------------------------------------------------
    confirmed_pos = po_data.get('purchase_orders', [])
    if confirmed_pos:
        score += 5
        subscores['po_exists'] = True
        feedback.append("PASS: Confirmed PO to SafePharm exists (+5)")
    else:
        subscores['po_exists'] = False
        feedback.append("FAIL: No confirmed PO to SafePharm Industries found")

    # ------------------------------------------------------------------
    # Criterion 6 (24 pts): PO quantities correct (8 pts each product)
    # ------------------------------------------------------------------
    po_lines = po_data.get('po_lines_by_product', {})
    for prod_code, expected_qty in EXPECTED_PO_QTY.items():
        actual_qty = po_lines.get(prod_code, 0)
        tolerance = expected_qty * 0.05  # +/- 5%

        if abs(actual_qty - expected_qty) <= tolerance:
            score += 8
            subscores['po_qty_{}'.format(prod_code)] = True
            feedback.append("PASS: PO for {} qty={} (expected {}) (+8)".format(
                prod_code, actual_qty, expected_qty))
        elif actual_qty > 0:
            score += 3
            subscores['po_qty_{}'.format(prod_code)] = 'partial'
            feedback.append("PARTIAL: PO for {} qty={} (expected {}) (+3)".format(
                prod_code, actual_qty, expected_qty))
        else:
            subscores['po_qty_{}'.format(prod_code)] = False
            feedback.append("FAIL: No PO line for {}".format(prod_code))

    # ------------------------------------------------------------------
    # Criterion 7 (5 pts): PO confirmed (not draft)
    # ------------------------------------------------------------------
    if confirmed_pos:
        all_confirmed = all(po.get('state') in ('purchase', 'done') for po in confirmed_pos)
        if all_confirmed:
            score += 5
            subscores['po_confirmed'] = True
            feedback.append("PASS: PO confirmed (state=purchase) (+5)")
        else:
            subscores['po_confirmed'] = False
            feedback.append("FAIL: PO exists but not confirmed")
    else:
        subscores['po_confirmed'] = False

    # ------------------------------------------------------------------
    # Criterion 8 (11 pts): Anti-gaming — control products untouched
    # ------------------------------------------------------------------
    ag_violated = False

    # Check Metformin lots (5.5 pts)
    met_ok = True
    for lot_name in ['MET-2024-022', 'MET-2024-045']:
        lot_data = lots.get(lot_name, {})
        expected = CONTROL_LOTS[lot_name]['qty']
        total = lot_data.get('total_internal_qty', 0)
        q_qty = lot_data.get('quarantine_qty', 0)
        if q_qty > 0 or abs(total - expected) > 0.01:
            met_ok = False
            feedback.append("FAIL (Anti-Gaming): Control lot {} was modified".format(lot_name))

    if met_ok:
        score += 5.5
        subscores['ag_metformin'] = True
        feedback.append("PASS: Metformin control lots untouched (+5.5)")
    else:
        subscores['ag_metformin'] = False
        ag_violated = True

    # Check Omeprazole lot (5.5 pts)
    omp_ok = True
    for lot_name in ['OMP-2024-019']:
        lot_data = lots.get(lot_name, {})
        expected = CONTROL_LOTS[lot_name]['qty']
        total = lot_data.get('total_internal_qty', 0)
        q_qty = lot_data.get('quarantine_qty', 0)
        if q_qty > 0 or abs(total - expected) > 0.01:
            omp_ok = False
            feedback.append("FAIL (Anti-Gaming): Control lot {} was modified".format(lot_name))

    if omp_ok:
        score += 5.5
        subscores['ag_omeprazole'] = True
        feedback.append("PASS: Omeprazole control lot untouched (+5.5)")
    else:
        subscores['ag_omeprazole'] = False
        ag_violated = True

    # Apply anti-gaming cap
    if ag_violated:
        score = min(score, 50)
        subscores['anti_gaming_passed'] = False
        feedback.append("PENALTY: Anti-gaming violation caps total score at 50")
    else:
        subscores['anti_gaming_passed'] = True

    # ------------------------------------------------------------------
    # Final result
    # ------------------------------------------------------------------
    score = min(score, 100)
    passed = (score >= pass_threshold) and subscores.get('anti_gaming_passed', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
    }
