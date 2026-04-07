#!/usr/bin/env python3
"""
Offline verifier unit tests for all 5 new odoo_inventory_env tasks.
Tests: do-nothing (passed=False), correct (passed=True), anti-gaming (capped score).
Per task_creation_notes/13_file_content_verification_and_offline_testing.md.
"""
import json
import importlib.util
import os
import sys
import tempfile

# Add task directories to path
TASKS_DIR = os.path.dirname(os.path.abspath(__file__))


def load_verifier(task_name, func_name):
    """Load a verifier function from a task directory using importlib (avoids import collisions)."""
    module_path = os.path.join(TASKS_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location(f'{task_name}_verifier', module_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return getattr(mod, func_name)

# ============================================================
# Helper: mock copy_from_env
# ============================================================
def make_env(result_data):
    """Create mock env_info with copy_from_env that serves result_data."""
    tf = tempfile.NamedTemporaryFile(suffix='.json', delete=False, mode='w')
    json.dump(result_data, tf)
    tf.close()
    src_path = tf.name

    def copy_from_env(remote_path, local_path):
        import shutil
        shutil.copy(src_path, local_path)

    return {'copy_from_env': copy_from_env}, src_path


def run_test(test_name, verify_fn, task_info, result_data, expect_passed, expect_score_range=None):
    """Run a single verifier test and check expectations."""
    env_info, tmp_path = make_env(result_data)
    try:
        out = verify_fn([], env_info, task_info)
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    passed = out.get('passed', None)
    score = out.get('score', -1)
    ok = True

    if passed != expect_passed:
        print(f"  FAIL {test_name}: expected passed={expect_passed}, got passed={passed}")
        ok = False
    if expect_score_range:
        lo, hi = expect_score_range
        if not (lo <= score <= hi):
            print(f"  FAIL {test_name}: expected score in [{lo},{hi}], got {score}")
            ok = False
    if ok:
        print(f"  PASS {test_name}: passed={passed}, score={score}")
    else:
        print(f"  DETAILS: {json.dumps(out, indent=2, default=str)}")
    return ok


# ============================================================
# Task 1: pharma_lot_quarantine_audit
# ============================================================
def test_pharma():
    print("\n=== Task 1: pharma_lot_quarantine_audit ===")
    verify_fn = load_verifier('pharma_lot_quarantine_audit', 'verify_pharma_lot_quarantine_audit')
    task_info = json.load(open(os.path.join(TASKS_DIR, 'pharma_lot_quarantine_audit/task.json')))
    all_ok = True

    # --- Do-nothing ---
    do_nothing = {
        'products': {
            'PHARMA-AMX-001': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-IBU-002': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-MET-003': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-LIS-004': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-OMP-005': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-ATV-006': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-AML-007': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-MTP-008': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
        },
        'quarantine_lots': {
            'LOT-AMX-2024-A': {'qty_in_quarantine': 0},
            'LOT-MET-2024-A': {'qty_in_quarantine': 0},
            'LOT-OMP-2024-B': {'qty_in_quarantine': 0},
        },
    }
    all_ok &= run_test("do-nothing", verify_fn, task_info, do_nothing,
                       expect_passed=False, expect_score_range=(0, 40))

    # --- Correct execution ---
    correct = {
        'products': {
            'PHARMA-AMX-001': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 50,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-IBU-002': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-MET-003': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 75,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-LIS-004': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-OMP-005': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 40,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-ATV-006': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-AML-007': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-MTP-008': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
        },
        'quarantine_lots': {
            'LOT-AMX-2024-A': {'qty_in_quarantine': 50},
            'LOT-MET-2024-A': {'qty_in_quarantine': 75},
            'LOT-OMP-2024-B': {'qty_in_quarantine': 40},
        },
    }
    all_ok &= run_test("correct", verify_fn, task_info, correct,
                       expect_passed=True, expect_score_range=(95, 100))

    # --- Anti-gaming: quarantine all lots ---
    gaming_quarantine = {
        'products': {
            'PHARMA-AMX-001': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 50,
                               'uses_correct_vendor': True,
                               'lots_in_quarantine': {'LOT-AMX-2024-A': 50, 'LOT-AMX-2024-B': 80}},
            'PHARMA-IBU-002': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False,
                               'lots_in_quarantine': {'LOT-IBU-2024-A': 200}},
            'PHARMA-MET-003': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 75,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-LIS-004': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-OMP-005': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 40,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-ATV-006': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-AML-007': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
            'PHARMA-MTP-008': {'found': True, 'has_confirmed_po': False, 'confirmed_po_qty': 0,
                               'uses_correct_vendor': False, 'lots_in_quarantine': {}},
        },
        'quarantine_lots': {
            'LOT-AMX-2024-A': {'qty_in_quarantine': 50},
            'LOT-MET-2024-A': {'qty_in_quarantine': 75},
            'LOT-OMP-2024-B': {'qty_in_quarantine': 40},
        },
    }
    all_ok &= run_test("anti-gaming-quarantine-all", verify_fn, task_info, gaming_quarantine,
                       expect_passed=False, expect_score_range=(0, 55))

    # --- Anti-gaming: order all products ---
    gaming_order_all = {
        'products': {
            'PHARMA-AMX-001': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 50,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-IBU-002': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 100,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-MET-003': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 75,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-LIS-004': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 100,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-OMP-005': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 40,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-ATV-006': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 50,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-AML-007': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 50,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
            'PHARMA-MTP-008': {'found': True, 'has_confirmed_po': True, 'confirmed_po_qty': 50,
                               'uses_correct_vendor': True, 'lots_in_quarantine': {}},
        },
        'quarantine_lots': {
            'LOT-AMX-2024-A': {'qty_in_quarantine': 50},
            'LOT-MET-2024-A': {'qty_in_quarantine': 75},
            'LOT-OMP-2024-B': {'qty_in_quarantine': 40},
        },
    }
    all_ok &= run_test("anti-gaming-order-all", verify_fn, task_info, gaming_order_all,
                       expect_passed=False, expect_score_range=(0, 55))

    return all_ok


# ============================================================
# Task 2: multi_warehouse_stock_rebalancing
# ============================================================
def test_multi_warehouse():
    print("\n=== Task 2: multi_warehouse_stock_rebalancing ===")
    verify_fn = load_verifier('multi_warehouse_stock_rebalancing', 'verify_multi_warehouse_stock_rebalancing')
    task_info = json.load(open(os.path.join(TASKS_DIR, 'multi_warehouse_stock_rebalancing/task.json')))
    all_ok = True

    wh_names = ['Main Warehouse', 'East Regional DC', 'West Regional DC']

    def make_prod(found, stock, has_transfer=False, transfers=None, all_transfers=None):
        return {
            'found': found,
            'current_stock': stock,
            'has_inter_wh_transfer': has_transfer,
            'inter_wh_transfers': transfers or [],
            'all_transfers': all_transfers or [],
        }

    # --- Do-nothing ---
    do_nothing = {'products': {
        'ELEC-TV-001': make_prod(True, {'Main Warehouse': 140, 'East Regional DC': 20, 'West Regional DC': 80}),
        'ELEC-LAP-002': make_prod(True, {'Main Warehouse': 30, 'East Regional DC': 130, 'West Regional DC': 40}),
        'ELEC-TAB-003': make_prod(True, {'Main Warehouse': 60, 'East Regional DC': 55, 'West Regional DC': 65}),
        'ELEC-PHN-004': make_prod(True, {'Main Warehouse': 180, 'East Regional DC': 20, 'West Regional DC': 10}),
        'ELEC-CAM-005': make_prod(True, {'Main Warehouse': 70, 'East Regional DC': 65, 'West Regional DC': 75}),
        'ELEC-SPK-006': make_prod(True, {'Main Warehouse': 10, 'East Regional DC': 160, 'West Regional DC': 10}),
        'ELEC-MON-007': make_prod(True, {'Main Warehouse': 55, 'East Regional DC': 60, 'West Regional DC': 62}),
        'ELEC-KBD-008': make_prod(True, {'Main Warehouse': 40, 'East Regional DC': 42, 'West Regional DC': 45}),
    }}
    all_ok &= run_test("do-nothing", verify_fn, task_info, do_nothing,
                       expect_passed=False, expect_score_range=(0, 40))

    # --- Correct execution ---
    correct = {'products': {
        'ELEC-TV-001': make_prod(True, {'Main Warehouse': 80, 'East Regional DC': 80, 'West Regional DC': 80},
                                 True, [{'state': 'done'}]),
        'ELEC-LAP-002': make_prod(True, {'Main Warehouse': 67, 'East Regional DC': 66, 'West Regional DC': 67},
                                   True, [{'state': 'done'}]),
        'ELEC-TAB-003': make_prod(True, {'Main Warehouse': 60, 'East Regional DC': 55, 'West Regional DC': 65}),
        'ELEC-PHN-004': make_prod(True, {'Main Warehouse': 70, 'East Regional DC': 70, 'West Regional DC': 70},
                                   True, [{'state': 'done'}]),
        'ELEC-CAM-005': make_prod(True, {'Main Warehouse': 70, 'East Regional DC': 65, 'West Regional DC': 75}),
        'ELEC-SPK-006': make_prod(True, {'Main Warehouse': 60, 'East Regional DC': 60, 'West Regional DC': 60},
                                   True, [{'state': 'done'}]),
        'ELEC-MON-007': make_prod(True, {'Main Warehouse': 55, 'East Regional DC': 60, 'West Regional DC': 62}),
        'ELEC-KBD-008': make_prod(True, {'Main Warehouse': 40, 'East Regional DC': 42, 'West Regional DC': 45}),
    }}
    all_ok &= run_test("correct", verify_fn, task_info, correct,
                       expect_passed=True, expect_score_range=(90, 100))

    # --- Anti-gaming: transfer all 8 products ---
    gaming = {'products': {
        'ELEC-TV-001': make_prod(True, {'Main Warehouse': 80, 'East Regional DC': 80, 'West Regional DC': 80},
                                 True, [{'state': 'done'}]),
        'ELEC-LAP-002': make_prod(True, {'Main Warehouse': 67, 'East Regional DC': 66, 'West Regional DC': 67},
                                   True, [{'state': 'done'}]),
        'ELEC-TAB-003': make_prod(True, {'Main Warehouse': 60, 'East Regional DC': 60, 'West Regional DC': 60},
                                   True, [{'state': 'done'}]),
        'ELEC-PHN-004': make_prod(True, {'Main Warehouse': 70, 'East Regional DC': 70, 'West Regional DC': 70},
                                   True, [{'state': 'done'}]),
        'ELEC-CAM-005': make_prod(True, {'Main Warehouse': 70, 'East Regional DC': 70, 'West Regional DC': 70},
                                   True, [{'state': 'done'}]),
        'ELEC-SPK-006': make_prod(True, {'Main Warehouse': 60, 'East Regional DC': 60, 'West Regional DC': 60},
                                   True, [{'state': 'done'}]),
        'ELEC-MON-007': make_prod(True, {'Main Warehouse': 59, 'East Regional DC': 59, 'West Regional DC': 59},
                                   True, [{'state': 'done'}]),
        'ELEC-KBD-008': make_prod(True, {'Main Warehouse': 42, 'East Regional DC': 42, 'West Regional DC': 43},
                                   True, [{'state': 'done'}]),
    }}
    all_ok &= run_test("anti-gaming-transfer-all", verify_fn, task_info, gaming,
                       expect_passed=False, expect_score_range=(0, 55))

    return all_ok


# ============================================================
# Task 3: vendor_disruption_procurement_pivot
# ============================================================
def test_vendor_disruption():
    print("\n=== Task 3: vendor_disruption_procurement_pivot ===")
    verify_fn = load_verifier('vendor_disruption_procurement_pivot', 'verify_vendor_disruption_procurement_pivot')
    task_info = json.load(open(os.path.join(TASKS_DIR, 'vendor_disruption_procurement_pivot/task.json')))
    all_ok = True

    def make_prod(found, cancelled=None, active_precision=None,
                  has_backup=False, backup_qty=0, confirmed=None, reorder_updated=False):
        return {
            'found': found,
            'cancelled_precision_pos': cancelled or [],
            'active_precision_pos': active_precision or [],
            'has_correct_backup_po': has_backup,
            'backup_po_qty': backup_qty,
            'new_backup_confirmed_pos': confirmed or [],
            'reorder_vendor_updated': reorder_updated,
        }

    base_products = {
        'AERO-AVN-005': make_prod(True),
        'AERO-CMP-006': make_prod(True),
        'AERO-RVT-007': make_prod(True),
        'AERO-BRG-008': make_prod(True),
        'AERO-SEL-009': make_prod(True),
        'AERO-SHM-010': make_prod(True),
    }
    protected_ok = {
        'AERO-CMP-006': {'still_intact': True, 'any_cancelled': False},
        'AERO-SEL-009': {'still_intact': True, 'any_cancelled': False},
    }

    # --- Do-nothing ---
    do_nothing_products = dict(base_products)
    for code in ['AERO-BRK-001', 'AERO-HYD-002', 'AERO-TRB-003', 'AERO-FAS-004']:
        do_nothing_products[code] = make_prod(True, active_precision=['PO-ORIG'])
    do_nothing = {'products': do_nothing_products, 'protected_pos_status': protected_ok}
    all_ok &= run_test("do-nothing", verify_fn, task_info, do_nothing,
                       expect_passed=False, expect_score_range=(0, 30))

    # --- Correct ---
    correct_products = dict(base_products)
    correct_products['AERO-BRK-001'] = make_prod(True, ['PO-C1'], [], True, 25, ['PO-N1'], True)
    correct_products['AERO-HYD-002'] = make_prod(True, ['PO-C2'], [], True, 40, ['PO-N2'], True)
    correct_products['AERO-TRB-003'] = make_prod(True, ['PO-C3'], [], True, 15, ['PO-N3'], True)
    correct_products['AERO-FAS-004'] = make_prod(True, ['PO-C4'], [], True, 100, ['PO-N4'], True)
    correct = {'products': correct_products, 'protected_pos_status': protected_ok}
    all_ok &= run_test("correct", verify_fn, task_info, correct,
                       expect_passed=True, expect_score_range=(95, 100))

    # --- Anti-gaming: cancel protected POs ---
    gaming_products = dict(correct_products)
    gaming_protected = {
        'AERO-CMP-006': {'still_intact': False, 'any_cancelled': True},
        'AERO-SEL-009': {'still_intact': True, 'any_cancelled': False},
    }
    gaming = {'products': gaming_products, 'protected_pos_status': gaming_protected}
    all_ok &= run_test("anti-gaming-cancel-protected", verify_fn, task_info, gaming,
                       expect_passed=False, expect_score_range=(0, 55))

    return all_ok


# ============================================================
# Task 4: cycle_count_discrepancy_resolution
# ============================================================
def test_cycle_count():
    print("\n=== Task 4: cycle_count_discrepancy_resolution ===")
    verify_fn = load_verifier('cycle_count_discrepancy_resolution', 'verify_cycle_count_discrepancy_resolution')
    task_info = json.load(open(os.path.join(TASKS_DIR, 'cycle_count_discrepancy_resolution/task.json')))
    all_ok = True

    def make_prod(found, initial, current, pending_qty=0, pending_picks=None):
        adjusted = abs(current - initial) > 0.01
        return {
            'found': found,
            'initial_qty': initial,
            'current_qty': current,
            'qty_was_adjusted': adjusted,
            'adjustment_amount': current - initial,
            'pending_transfer_qty': pending_qty,
            'pending_picking_ids': pending_picks or [],
        }

    # --- Do-nothing ---
    do_nothing = {
        'stock_location_id': 8,
        'products': {
            'MRO-PMP-001': make_prod(True, 45, 45),
            'MRO-VLV-002': make_prod(True, 120, 120),
            'MRO-BRG-003': make_prod(True, 300, 300),
            'MRO-MTR-004': make_prod(True, 18, 18, 3),
            'MRO-FLT-005': make_prod(True, 200, 200),
            'MRO-GKT-006': make_prod(True, 85, 85),
            'MRO-CHP-007': make_prod(True, 50, 50),
            'MRO-WHL-008': make_prod(True, 65, 65, 5),
            'MRO-SHF-009': make_prod(True, 30, 30),
            'MRO-CLN-010': make_prod(True, 40, 40),
        }
    }
    all_ok &= run_test("do-nothing", verify_fn, task_info, do_nothing,
                       expect_passed=False, expect_score_range=(30, 45))

    # --- Correct: adjust only shrinkage products ---
    correct = {
        'stock_location_id': 8,
        'products': {
            'MRO-PMP-001': make_prod(True, 45, 42),      # adjusted -3
            'MRO-VLV-002': make_prod(True, 120, 120),     # no change
            'MRO-BRG-003': make_prod(True, 300, 285),     # adjusted -15
            'MRO-MTR-004': make_prod(True, 18, 18, 3),    # NOT adjusted (pending)
            'MRO-FLT-005': make_prod(True, 200, 200),     # no change
            'MRO-GKT-006': make_prod(True, 85, 78),       # adjusted -7
            'MRO-CHP-007': make_prod(True, 50, 50),       # no change
            'MRO-WHL-008': make_prod(True, 65, 65, 5),    # NOT adjusted (pending)
            'MRO-SHF-009': make_prod(True, 30, 25),       # adjusted -5
            'MRO-CLN-010': make_prod(True, 40, 40),       # no change
        }
    }
    all_ok &= run_test("correct", verify_fn, task_info, correct,
                       expect_passed=True, expect_score_range=(95, 100))

    # --- Anti-gaming: adjust all discrepancy products (including pending) ---
    gaming = {
        'stock_location_id': 8,
        'products': {
            'MRO-PMP-001': make_prod(True, 45, 42),
            'MRO-VLV-002': make_prod(True, 120, 120),
            'MRO-BRG-003': make_prod(True, 300, 285),
            'MRO-MTR-004': make_prod(True, 18, 15, 3),    # WRONGLY adjusted
            'MRO-FLT-005': make_prod(True, 200, 200),
            'MRO-GKT-006': make_prod(True, 85, 78),
            'MRO-CHP-007': make_prod(True, 50, 50),
            'MRO-WHL-008': make_prod(True, 65, 60, 5),    # WRONGLY adjusted
            'MRO-SHF-009': make_prod(True, 30, 25),
            'MRO-CLN-010': make_prod(True, 40, 40),
        }
    }
    all_ok &= run_test("anti-gaming-adjust-pending", verify_fn, task_info, gaming,
                       expect_passed=False, expect_score_range=(0, 55))

    return all_ok


# ============================================================
# Task 5: safety_stock_seasonal_reconfiguration
# ============================================================
def test_seasonal():
    print("\n=== Task 5: safety_stock_seasonal_reconfiguration ===")
    verify_fn = load_verifier('safety_stock_seasonal_reconfiguration', 'verify_safety_stock_seasonal_reconfiguration')
    task_info = json.load(open(os.path.join(TASKS_DIR, 'safety_stock_seasonal_reconfiguration/task.json')))
    all_ok = True

    winter_codes = ['AGR-HEAT-001', 'AGR-SALT-002', 'AGR-ANTF-003',
                    'AGR-INSL-004', 'AGR-SNOW-005', 'AGR-DICE-006']
    spring_codes = ['AGR-SEED-007', 'AGR-FERT-008', 'AGR-PEST-009',
                    'AGR-IRRI-010', 'AGR-MULC-011', 'AGR-TREL-012']

    # --- Do-nothing ---
    do_nothing_prods = {}
    for code in winter_codes:
        do_nothing_prods[code] = {
            'found': True, 'initial_had_rule': True, 'has_active_rule': True,
            'rule_min_qty': 50, 'rule_max_qty': 200,
            'has_confirmed_po': False, 'confirmed_po_qty': 0,
            'uses_correct_vendor': False, 'initial_qty': 100,
        }
    for code in spring_codes:
        do_nothing_prods[code] = {
            'found': True, 'initial_had_rule': False, 'has_active_rule': False,
            'rule_min_qty': 0, 'rule_max_qty': 0,
            'has_confirmed_po': False, 'confirmed_po_qty': 0,
            'uses_correct_vendor': False, 'initial_qty': 50,
        }
    do_nothing = {'products': do_nothing_prods}
    all_ok &= run_test("do-nothing", verify_fn, task_info, do_nothing,
                       expect_passed=False, expect_score_range=(0, 30))

    # --- Correct ---
    correct_prods = {}
    for code in winter_codes:
        correct_prods[code] = {
            'found': True, 'initial_had_rule': True, 'has_active_rule': False,
            'rule_min_qty': 0, 'rule_max_qty': 0,
            'has_confirmed_po': False, 'confirmed_po_qty': 0,
            'uses_correct_vendor': False, 'initial_qty': 100,
        }
    spring_targets = {
        'AGR-SEED-007': {'min': 100, 'max': 500},
        'AGR-FERT-008': {'min': 200, 'max': 800},
        'AGR-PEST-009': {'min': 80, 'max': 300},
        'AGR-IRRI-010': {'min': 100, 'max': 400},
        'AGR-MULC-011': {'min': 150, 'max': 600},
        'AGR-TREL-012': {'min': 100, 'max': 400},
    }
    initial_qtys = {
        'AGR-SEED-007': 20, 'AGR-FERT-008': 50, 'AGR-PEST-009': 15,
        'AGR-IRRI-010': 250, 'AGR-MULC-011': 180, 'AGR-TREL-012': 300,
    }
    for code in spring_codes:
        t = spring_targets[code]
        iq = initial_qtys[code]
        needs_po = code in ['AGR-SEED-007', 'AGR-FERT-008', 'AGR-PEST-009']
        correct_prods[code] = {
            'found': True, 'initial_had_rule': False, 'has_active_rule': True,
            'rule_min_qty': t['min'], 'rule_max_qty': t['max'],
            'has_confirmed_po': needs_po,
            'confirmed_po_qty': t['max'] - iq if needs_po else 0,
            'uses_correct_vendor': needs_po,
            'initial_qty': iq,
        }
    correct = {'products': correct_prods}
    all_ok &= run_test("correct", verify_fn, task_info, correct,
                       expect_passed=True, expect_score_range=(95, 100))

    # --- Anti-gaming: order all spring products ---
    gaming_prods = dict(correct_prods)
    for code in ['AGR-IRRI-010', 'AGR-MULC-011', 'AGR-TREL-012']:
        gaming_prods[code] = dict(gaming_prods[code])
        gaming_prods[code]['has_confirmed_po'] = True
        gaming_prods[code]['confirmed_po_qty'] = 100
    gaming = {'products': gaming_prods}
    all_ok &= run_test("anti-gaming-order-all-spring", verify_fn, task_info, gaming,
                       expect_passed=False, expect_score_range=(0, 55))

    return all_ok


# ============================================================
# Main
# ============================================================
if __name__ == '__main__':
    os.chdir(TASKS_DIR)
    results = []
    results.append(('pharma_lot_quarantine_audit', test_pharma()))
    results.append(('multi_warehouse_stock_rebalancing', test_multi_warehouse()))
    results.append(('vendor_disruption_procurement_pivot', test_vendor_disruption()))
    results.append(('cycle_count_discrepancy_resolution', test_cycle_count()))
    results.append(('safety_stock_seasonal_reconfiguration', test_seasonal()))

    print("\n" + "=" * 60)
    all_passed = True
    for name, ok in results:
        status = "PASS" if ok else "FAIL"
        print(f"  {status}: {name}")
        all_passed &= ok

    if all_passed:
        print("\nAll offline verifier tests PASSED.")
    else:
        print("\nSome tests FAILED.")
        sys.exit(1)
