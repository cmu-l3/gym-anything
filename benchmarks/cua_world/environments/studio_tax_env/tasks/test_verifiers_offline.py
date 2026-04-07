#!/usr/bin/env python3
"""Offline unit tests for all 5 new studio_tax_env verifiers.

Tests three scenarios for each verifier:
  1. Do-nothing: result file missing (copy_from_env raises FileNotFoundError)
  2. Wrong-target / empty: file missing or no data
  3. Full completion: correct result dict with all expected fields
  4. Partial completion: some fields correct, some missing

Run with: python3 test_verifiers_offline.py
"""

import importlib.util
import json
import os
import sys
import tempfile

TASKS_DIR = os.path.dirname(os.path.abspath(__file__))


def load_verifier(task_name):
    path = os.path.join(TASKS_DIR, task_name, 'verifier.py')
    spec = importlib.util.spec_from_file_location('verifier', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_env(result_data):
    """Return env_info with copy_from_env that writes result_data as JSON."""
    def copy_from_env(src, dst):
        with open(dst, 'w', encoding='utf-8') as f:
            json.dump(result_data, f)
    return {'copy_from_env': copy_from_env}


def make_env_missing():
    """Simulate result file not yet written (agent did nothing)."""
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file: {src}")
    return {'copy_from_env': copy_from_env}


# ============================================================
# Task 1: gig_economy_self_employment
# ============================================================

def test_gig_economy():
    mod = load_verifier('gig_economy_self_employment')
    fn = mod.verify_gig_economy_self_employment
    task_info = {}

    # Do-nothing (result file missing)
    r = fn([], make_env_missing(), task_info)
    assert r['passed'] is False, f"Do-nothing must fail: {r}"
    assert r['score'] == 0, f"Do-nothing score must be 0: {r}"
    print(f"  [gig_economy] do-nothing: passed={r['passed']}, score={r['score']} ✓")

    # Wrong target (file exists but wrong person)
    wrong = {
        'file_exists': True, 'file_size_bytes': 3000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_papadopoulos': False, 'contains_dimitri': False,
        'contains_34840': False, 'contains_12180': False, 'contains_47020': False,
        'contains_7679': False, 'contains_2697': False, 'contains_35527': False,
        'contains_self_employ': False, 'contains_ontario': True,
    }
    r = fn([], make_env(wrong), task_info)
    assert r['passed'] is False, f"Wrong-target must fail: {r}"
    assert r['score'] <= 55, f"Score cap should apply (max 55): {r}"
    print(f"  [gig_economy] wrong-target: passed={r['passed']}, score={r['score']} ✓")

    # Partial completion (Uber income but not DoorDash)
    partial = {
        'file_exists': True, 'file_size_bytes': 6000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_papadopoulos': True, 'contains_dimitri': True,
        'contains_34840': True, 'contains_12180': False, 'contains_47020': False,
        'contains_7679': True, 'contains_2697': False, 'contains_35527': False,
        'contains_self_employ': True, 'contains_ontario': True,
    }
    r = fn([], make_env(partial), task_info)
    assert r['passed'] is False, f"Partial should not pass: {r}"
    assert 20 <= r['score'] <= 55, f"Partial score range 20-55: {r}"
    print(f"  [gig_economy] partial: passed={r['passed']}, score={r['score']} ✓")

    # Full completion
    full = {
        'file_exists': True, 'file_size_bytes': 8500, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_papadopoulos': True, 'contains_dimitri': True,
        'contains_34840': True, 'contains_12180': True, 'contains_47020': True,
        'contains_7679': True, 'contains_2697': True, 'contains_35527': True,
        'contains_self_employ': True, 'contains_ontario': True,
    }
    r = fn([], make_env(full), task_info)
    assert r['passed'] is True, f"Full completion should pass: {r}"
    assert r['score'] >= 60, f"Full score must be >= 60: {r}"
    print(f"  [gig_economy] full: passed={r['passed']}, score={r['score']} ✓")


# ============================================================
# Task 2: crypto_day_trader_return
# ============================================================

def test_crypto():
    mod = load_verifier('crypto_day_trader_return')
    fn = mod.verify_crypto_day_trader_return
    task_info = {}

    r = fn([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Do-nothing: {r}"
    print(f"  [crypto] do-nothing: passed={r['passed']}, score={r['score']} ✓")

    wrong = {
        'file_exists': True, 'file_size_bytes': 2000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_nair': False, 'contains_priya': False,
        'contains_72500': False, 'contains_1840': False,
        'contains_7600': False, 'contains_6400': False,
        'contains_16800': False, 'contains_2100': False,
        'contains_5500': False, 'contains_2288': False, 'contains_2202': False,
        'contains_bc': True, 'contains_capgain': False,
    }
    r = fn([], make_env(wrong), task_info)
    assert r['passed'] is False, f"Wrong-target: {r}"
    assert r['score'] <= 55, f"Score cap: {r}"
    print(f"  [crypto] wrong-target: passed={r['passed']}, score={r['score']} ✓")

    partial = {
        'file_exists': True, 'file_size_bytes': 5000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_nair': True, 'contains_priya': True,
        'contains_72500': True, 'contains_1840': False,
        'contains_7600': True, 'contains_6400': False,
        'contains_16800': False, 'contains_2100': False,
        'contains_5500': False, 'contains_2288': False, 'contains_2202': False,
        'contains_bc': True, 'contains_capgain': True,
    }
    r = fn([], make_env(partial), task_info)
    assert r['passed'] is False, f"Partial should not pass: {r}"
    assert 25 <= r['score'] <= 59, f"Partial score range: {r}"
    print(f"  [crypto] partial: passed={r['passed']}, score={r['score']} ✓")

    full = {
        'file_exists': True, 'file_size_bytes': 8000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_nair': True, 'contains_priya': True,
        'contains_72500': True, 'contains_1840': True,
        'contains_7600': True, 'contains_6400': True,
        'contains_16800': True, 'contains_2100': True,
        'contains_5500': True, 'contains_2288': True, 'contains_2202': False,
        'contains_bc': True, 'contains_capgain': True,
    }
    r = fn([], make_env(full), task_info)
    assert r['passed'] is True, f"Full should pass: {r}"
    assert r['score'] >= 60, f"Full score: {r}"
    print(f"  [crypto] full: passed={r['passed']}, score={r['score']} ✓")


# ============================================================
# Task 3: locum_physician_self_employment
# ============================================================

def test_physician():
    mod = load_verifier('locum_physician_self_employment')
    fn = mod.verify_locum_physician_self_employment
    task_info = {}

    r = fn([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Do-nothing: {r}"
    print(f"  [physician] do-nothing: passed={r['passed']}, score={r['score']} ✓")

    wrong = {
        'file_exists': True, 'file_size_bytes': 2500, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_kamara': False, 'contains_aisha': False,
        'contains_145000': False, 'contains_48000': False,
        'contains_8615': False, 'contains_1675': False, 'contains_3200': False,
        'contains_39385': False, 'contains_28900': False, 'contains_12650': False,
        'contains_2100': False, 'contains_ontario': True, 'contains_38400': False,
        'contains_self_employ': False,
    }
    r = fn([], make_env(wrong), task_info)
    assert r['passed'] is False, f"Wrong-target: {r}"
    assert r['score'] <= 55, f"Score cap: {r}"
    print(f"  [physician] wrong-target: passed={r['passed']}, score={r['score']} ✓")

    partial = {
        'file_exists': True, 'file_size_bytes': 6000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_kamara': True, 'contains_aisha': True,
        'contains_145000': True, 'contains_48000': False,
        'contains_8615': False, 'contains_1675': True, 'contains_3200': False,
        'contains_39385': False, 'contains_28900': False, 'contains_12650': True,
        'contains_2100': True, 'contains_ontario': True, 'contains_38400': False,
        'contains_self_employ': True,
    }
    r = fn([], make_env(partial), task_info)
    assert r['passed'] is False, f"Partial should not pass: {r}"
    assert 20 <= r['score'] <= 55, f"Partial score range: {r}"
    print(f"  [physician] partial: passed={r['passed']}, score={r['score']} ✓")

    full = {
        'file_exists': True, 'file_size_bytes': 9000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_kamara': True, 'contains_aisha': True,
        'contains_145000': True, 'contains_48000': True,
        'contains_8615': True, 'contains_1675': True, 'contains_3200': True,
        'contains_39385': True, 'contains_28900': True, 'contains_12650': True,
        'contains_2100': True, 'contains_ontario': True, 'contains_38400': True,
        'contains_self_employ': True,
    }
    r = fn([], make_env(full), task_info)
    assert r['passed'] is True, f"Full should pass: {r}"
    assert r['score'] >= 60, f"Full score: {r}"
    print(f"  [physician] full: passed={r['passed']}, score={r['score']} ✓")


# ============================================================
# Task 4: real_estate_agent_expenses
# ============================================================

def test_realestate():
    mod = load_verifier('real_estate_agent_expenses')
    fn = mod.verify_real_estate_agent_expenses
    task_info = {}

    r = fn([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Do-nothing: {r}"
    print(f"  [realestate] do-nothing: passed={r['passed']}, score={r['score']} ✓")

    wrong = {
        'file_exists': True, 'file_size_bytes': 2000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_espinoza': False, 'contains_rodrigo': False,
        'contains_36000': False, 'contains_87500': False,
        'contains_10630': False, 'contains_8342': False, 'contains_6217': False,
        'contains_40478': False, 'contains_47022': False,
        'contains_10000': False, 'contains_500': False,
        'contains_alberta': True, 'contains_common_law': False, 'contains_6770': False,
    }
    r = fn([], make_env(wrong), task_info)
    assert r['passed'] is False, f"Wrong-target: {r}"
    assert r['score'] <= 55, f"Score cap: {r}"
    print(f"  [realestate] wrong-target: passed={r['passed']}, score={r['score']} ✓")

    partial = {
        'file_exists': True, 'file_size_bytes': 5500, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_espinoza': True, 'contains_rodrigo': True,
        'contains_36000': True, 'contains_87500': False,  # Missing commission!
        'contains_10630': True, 'contains_8342': False, 'contains_6217': False,
        'contains_40478': False, 'contains_47022': False,
        'contains_10000': True, 'contains_500': False,
        'contains_alberta': True, 'contains_common_law': False, 'contains_6770': False,
    }
    r = fn([], make_env(partial), task_info)
    assert r['passed'] is False, f"Partial should not pass: {r}"
    assert r['score'] <= 55, f"Score cap applies: {r}"
    print(f"  [realestate] partial: passed={r['passed']}, score={r['score']} ✓")

    full = {
        'file_exists': True, 'file_size_bytes': 9500, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_espinoza': True, 'contains_rodrigo': True,
        'contains_36000': True, 'contains_87500': True,
        'contains_10630': True, 'contains_8342': True, 'contains_6217': True,
        'contains_40478': True, 'contains_47022': True,
        'contains_10000': True, 'contains_500': True,
        'contains_alberta': True, 'contains_common_law': True, 'contains_6770': True,
    }
    r = fn([], make_env(full), task_info)
    assert r['passed'] is True, f"Full should pass: {r}"
    assert r['score'] >= 60, f"Full score: {r}"
    print(f"  [realestate] full: passed={r['passed']}, score={r['score']} ✓")


# ============================================================
# Task 5: newcomer_partial_year_return
# ============================================================

def test_newcomer():
    mod = load_verifier('newcomer_partial_year_return')
    fn = mod.verify_newcomer_partial_year_return
    task_info = {}

    r = fn([], make_env_missing(), task_info)
    assert r['passed'] is False and r['score'] == 0, f"Do-nothing: {r}"
    print(f"  [newcomer] do-nothing: passed={r['passed']}, score={r['score']} ✓")

    # Wrong-target (file exists but for wrong person, no arrival date)
    wrong = {
        'file_exists': True, 'file_size_bytes': 2500, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_osei': False, 'contains_mensah': False, 'contains_amara': False,
        'contains_52800': False, 'contains_2640': False, 'contains_10320': False,
        'contains_4000': False, 'contains_1800': False, 'contains_26550': False,
        'contains_arrival_date': False, 'contains_ontario': True,
        'contains_part_year': False, 'contains_kwame': False,
    }
    r = fn([], make_env(wrong), task_info)
    assert r['passed'] is False, f"Wrong-target: {r}"
    assert r['score'] <= 45, f"Score cap (no arrival date): {r}"
    print(f"  [newcomer] wrong-target: passed={r['passed']}, score={r['score']} ✓")

    # Partial (T4 entered but no arrival date — full-year resident mistake)
    partial_wrong = {
        'file_exists': True, 'file_size_bytes': 4000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_osei': True, 'contains_mensah': True, 'contains_amara': True,
        'contains_52800': True, 'contains_2640': True, 'contains_10320': True,
        'contains_4000': False, 'contains_1800': False, 'contains_26550': False,
        'contains_arrival_date': False, 'contains_ontario': True,
        'contains_part_year': False, 'contains_kwame': False,
    }
    r = fn([], make_env(partial_wrong), task_info)
    assert r['passed'] is False, f"Partial (no arrival date) should not pass: {r}"
    assert r['score'] <= 45, f"Score cap for missing arrival date: {r}"
    print(f"  [newcomer] partial-no-arrival-date: passed={r['passed']}, score={r['score']} ✓")

    # Full completion
    full = {
        'file_exists': True, 'file_size_bytes': 7000, 'file_mod_time': 9999999999,
        'start_timestamp': 1000, 'file_is_new': True,
        'contains_osei': True, 'contains_mensah': True, 'contains_amara': True,
        'contains_52800': True, 'contains_2640': True, 'contains_10320': True,
        'contains_4000': True, 'contains_1800': True, 'contains_26550': True,
        'contains_arrival_date': True, 'contains_ontario': True,
        'contains_part_year': True, 'contains_kwame': True,
    }
    r = fn([], make_env(full), task_info)
    assert r['passed'] is True, f"Full should pass: {r}"
    assert r['score'] >= 60, f"Full score: {r}"
    print(f"  [newcomer] full: passed={r['passed']}, score={r['score']} ✓")


# ============================================================
# Run all tests
# ============================================================

if __name__ == '__main__':
    print("=== Offline Verifier Unit Tests — 5 New StudioTax Tasks ===\n")
    tests = [
        ("Task 1: gig_economy_self_employment", test_gig_economy),
        ("Task 2: crypto_day_trader_return", test_crypto),
        ("Task 3: locum_physician_self_employment", test_physician),
        ("Task 4: real_estate_agent_expenses", test_realestate),
        ("Task 5: newcomer_partial_year_return", test_newcomer),
    ]
    passed = 0
    failed = 0
    for name, fn in tests:
        print(f"\n{name}")
        try:
            fn()
            passed += 1
        except AssertionError as e:
            print(f"  ASSERTION FAILED: {e}")
            failed += 1
        except Exception as e:
            print(f"  ERROR: {e}")
            import traceback
            traceback.print_exc()
            failed += 1

    print(f"\n=== Results: {passed}/{len(tests)} test suites passed, {failed} failed ===")
    sys.exit(0 if failed == 0 else 1)
