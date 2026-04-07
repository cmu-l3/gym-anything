import json
import os
import tempfile


def verify_vendor_disruption_procurement_pivot(traj, env_info, task_info):
    """
    Verify vendor disruption procurement pivot for aerospace parts.

    Scoring (100 pts total, pass threshold: 80):
      15 pts — All 4 affected pending POs cancelled (state='cancel')
      25 pts — New POs created with correct backup vendors for all 4 products (6.25 each)
      10 pts — New PO quantities match original requirements (25, 40, 15, 100)
      15 pts — New POs confirmed (state='purchase'), not draft
      10 pts — Correct backup vendor selected per product (SkyTech for 001/002, AeroAlloy for 003/004)
      10 pts — Reorder rules updated to reference backup vendor
      15 pts — Anti-gaming: unaffected POs untouched (if AERO-CMP-006 or AERO-SEL-009 PO modified/cancelled, cap at 55)

    Strategy enumeration:
      Do-nothing:            0+0+0+0+0+0+15 = 15          → FAIL
      Cancel all POs:        15+0+0+0+0+0+0 (capped 55)   → FAIL
      Correct execution:     15+25+10+15+10+10+15 = 100    → PASS
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/vendor_disruption_pivot_result.json')
    pass_threshold = metadata.get('pass_threshold', 80)
    affected_codes = metadata.get('affected_codes',
                                   ['AERO-BRK-001', 'AERO-HYD-002', 'AERO-TRB-003', 'AERO-FAS-004'])
    unaffected_codes = metadata.get('unaffected_codes',
                                     ['AERO-AVN-005', 'AERO-CMP-006', 'AERO-RVT-007',
                                      'AERO-BRG-008', 'AERO-SEL-009', 'AERO-SHM-010'])
    protected_po_products = metadata.get('protected_po_products', ['AERO-CMP-006', 'AERO-SEL-009'])
    backup_vendors = metadata.get('backup_vendors', {
        'AERO-BRK-001': 'SkyTech Components Ltd.',
        'AERO-HYD-002': 'SkyTech Components Ltd.',
        'AERO-TRB-003': 'AeroAlloy Materials Corp.',
        'AERO-FAS-004': 'AeroAlloy Materials Corp.',
    })
    original_quantities = metadata.get('original_quantities', {
        'AERO-BRK-001': 25,
        'AERO-HYD-002': 40,
        'AERO-TRB-003': 15,
        'AERO-FAS-004': 100,
    })

    score = 0
    subscores = {}
    feedback_parts = []

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export file not found: {e}",
            "subscores": {},
        }

    try:
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse export result: {e}",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    products = result.get('products', {})

    # Sanity check: at least some products exist
    found_count = sum(1 for p in products.values() if p.get('found', False))
    if found_count < 8:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Only {found_count}/10 products found — environment setup may have failed",
            "subscores": {},
        }

    # --- Criterion 1 (15 pts): All 4 affected pending POs cancelled ---
    cancelled_count = 0
    for code in affected_codes:
        prod_data = products.get(code, {})
        cancelled_pos = prod_data.get('cancelled_precision_pos', [])
        active_pos = prod_data.get('active_precision_pos', [])
        if cancelled_pos and not active_pos:
            cancelled_count += 1
            subscores[f'cancelled_{code}'] = True
        else:
            subscores[f'cancelled_{code}'] = False

    if cancelled_count == 4:
        score += 15
        feedback_parts.append(f"PASS: All 4 affected POs cancelled (+15)")
    elif cancelled_count > 0:
        partial = round(15 * cancelled_count / 4, 2)
        score += partial
        feedback_parts.append(f"PARTIAL: {cancelled_count}/4 affected POs cancelled (+{partial})")
    else:
        feedback_parts.append("FAIL: No affected POs cancelled")

    # --- Criterion 2 (25 pts): New POs created with correct backup vendors ---
    new_po_count = 0
    for code in affected_codes:
        prod_data = products.get(code, {})
        has_backup_po = prod_data.get('has_correct_backup_po', False)
        if has_backup_po:
            new_po_count += 1
            score += 6.25
            subscores[f'new_po_{code}'] = True
            feedback_parts.append(f"PASS: New PO with backup vendor for {code} (+6.25)")
        else:
            subscores[f'new_po_{code}'] = False
            feedback_parts.append(f"FAIL: No confirmed PO with correct backup vendor for {code}")

    # --- Criterion 3 (10 pts): New PO quantities match original requirements ---
    qty_match_count = 0
    for code in affected_codes:
        prod_data = products.get(code, {})
        backup_qty = prod_data.get('backup_po_qty', 0)
        expected_qty = original_quantities.get(code, 0)
        # Allow within 10% tolerance
        if expected_qty > 0 and abs(backup_qty - expected_qty) <= expected_qty * 0.10:
            qty_match_count += 1
            subscores[f'qty_{code}'] = True
        else:
            subscores[f'qty_{code}'] = False

    if qty_match_count == 4:
        score += 10
        feedback_parts.append(f"PASS: All 4 new PO quantities match originals (+10)")
    elif qty_match_count > 0:
        partial = round(10 * qty_match_count / 4, 2)
        score += partial
        feedback_parts.append(f"PARTIAL: {qty_match_count}/4 quantities match (+{partial})")
    else:
        feedback_parts.append("FAIL: No new PO quantities match original requirements")

    # --- Criterion 4 (15 pts): New POs confirmed (state='purchase'), not draft ---
    confirmed_count = 0
    for code in affected_codes:
        prod_data = products.get(code, {})
        confirmed_pos = prod_data.get('new_backup_confirmed_pos', [])
        if confirmed_pos:
            confirmed_count += 1
            subscores[f'confirmed_{code}'] = True
        else:
            subscores[f'confirmed_{code}'] = False

    if confirmed_count == 4:
        score += 15
        feedback_parts.append(f"PASS: All 4 new POs confirmed (+15)")
    elif confirmed_count > 0:
        partial = round(15 * confirmed_count / 4, 2)
        score += partial
        feedback_parts.append(f"PARTIAL: {confirmed_count}/4 new POs confirmed (+{partial})")
    else:
        feedback_parts.append("FAIL: No new POs confirmed")

    # --- Criterion 5 (10 pts): Correct backup vendor selected per product ---
    vendor_correct_count = 0
    for code in affected_codes:
        prod_data = products.get(code, {})
        if prod_data.get('has_correct_backup_po', False):
            vendor_correct_count += 1

    if vendor_correct_count >= 4:
        score += 10
        subscores['correct_backup_vendors'] = True
        feedback_parts.append(f"PASS: Correct backup vendor for all 4 products (+10)")
    elif vendor_correct_count >= 2:
        partial = round(10 * vendor_correct_count / 4, 2)
        score += partial
        subscores['correct_backup_vendors'] = 'partial'
        feedback_parts.append(f"PARTIAL: Correct backup vendor for {vendor_correct_count}/4 (+{partial})")
    else:
        subscores['correct_backup_vendors'] = False
        feedback_parts.append(f"FAIL: Correct backup vendor for only {vendor_correct_count}/4")

    # --- Criterion 6 (10 pts): Reorder rules updated to reference backup vendor ---
    reorder_updated_count = 0
    for code in affected_codes:
        prod_data = products.get(code, {})
        if prod_data.get('reorder_vendor_updated', False):
            reorder_updated_count += 1
            subscores[f'reorder_{code}'] = True
        else:
            subscores[f'reorder_{code}'] = False

    if reorder_updated_count == 4:
        score += 10
        feedback_parts.append(f"PASS: All 4 reorder rules updated to backup vendor (+10)")
    elif reorder_updated_count > 0:
        partial = round(10 * reorder_updated_count / 4, 2)
        score += partial
        feedback_parts.append(f"PARTIAL: {reorder_updated_count}/4 reorder rules updated (+{partial})")
    else:
        feedback_parts.append("FAIL: No reorder rules updated to backup vendor")

    # --- Criterion 7 (15 pts): Anti-gaming — unaffected POs untouched ---
    protected_pos_status = result.get('protected_pos_status', {})
    protected_violated = False
    for code in protected_po_products:
        status = protected_pos_status.get(code, {})
        if not status.get('still_intact', True) or status.get('any_cancelled', False):
            protected_violated = True
            subscores[f'protected_{code}'] = False
            feedback_parts.append(
                f"FAIL: Protected PO for {code} was modified or cancelled — anti-gaming violation"
            )
        else:
            subscores[f'protected_{code}'] = True

    if not protected_violated:
        score += 15
        subscores['anti_gaming_unaffected_untouched'] = True
        feedback_parts.append("PASS: Unaffected POs left intact (+15)")
    else:
        subscores['anti_gaming_unaffected_untouched'] = False
        feedback_parts.append(
            "FAIL: Unaffected POs were disturbed — this caps achievable score at 55"
        )
        # Hard cap: touching protected POs makes passing impossible
        score = min(score, 55)

    # Cap at 100
    score = min(score, 100)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "pass_threshold": pass_threshold,
            "cancelled_count": cancelled_count,
            "new_po_count": new_po_count,
            "qty_match_count": qty_match_count,
            "confirmed_count": confirmed_count,
            "vendor_correct_count": vendor_correct_count,
            "reorder_updated_count": reorder_updated_count,
            "protected_violated": protected_violated,
        },
    }
