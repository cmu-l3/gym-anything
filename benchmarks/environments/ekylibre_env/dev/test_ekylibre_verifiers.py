#!/usr/bin/env python3
"""
Programmatic validation tests for ekylibre_env tasks.

Tests do-nothing, wrong-target, and partial completion scenarios for each verifier
without requiring the VM to be running.

Usage:
    python3 benchmarks/environments/ekylibre_env/dev/test_ekylibre_verifiers.py
"""

import sys
import os
import json
import shutil
import tempfile
import importlib.util

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))

TASKS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tasks")
PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"


def make_copy_fn(result_json: dict):
    """Return a copy_from_env that serves a given dict as the result file."""
    def copy_from_env(src_path, dst_path):
        with open(dst_path, "w") as f:
            json.dump(result_json, f)
    return copy_from_env


def load_verifier(task_name):
    """Dynamically load verifier.py for a given task."""
    verifier_path = os.path.join(TASKS_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location(f"verifier_{task_name}", verifier_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    fn_name = f"verify_{task_name}"
    return getattr(mod, fn_name)


def run_verifier(fn, result_json, task_info=None):
    env_info = {"copy_from_env": make_copy_fn(result_json)}
    task_info = task_info or {}
    result = fn([], env_info, task_info)
    return result


def check(label, result, expect_passed, expect_score_max=None, expect_score_min=None):
    passed_ok = result["passed"] == expect_passed
    score = result["score"]
    score_ok = True
    if expect_score_max is not None:
        score_ok = score_ok and (score <= expect_score_max)
    if expect_score_min is not None:
        score_ok = score_ok and (score >= expect_score_min)

    ok = passed_ok and score_ok
    status = PASS if ok else FAIL
    print(f"  [{status}] {label}: passed={result['passed']}, score={score}")
    if not ok:
        print(f"         Expected: passed={expect_passed}, score in "
              f"[{expect_score_min},{expect_score_max}]")
        print(f"         Feedback: {result.get('feedback','')[:100]}")
    return ok


# ─────────────────────────────────────────────────────────────────────────────
# Task 1: crop_rotation_plan_for_compliance
# ─────────────────────────────────────────────────────────────────────────────
def test_crop_rotation():
    print("\n[crop_rotation_plan_for_compliance]")
    fn = load_verifier("crop_rotation_plan_for_compliance")
    results = []

    # Do-nothing: no new productions
    r = run_verifier(fn, {"new_productions_count": 0, "distinct_activities_count": 0,
                          "productions_in_2024_campaign": 0, "productions_with_support": 0})
    results.append(check("do-nothing", r, expect_passed=False, expect_score_max=0))

    # Wrong-target: only 1 production with wrong campaign
    r = run_verifier(fn, {"new_productions_count": 1, "distinct_activities_count": 1,
                          "productions_in_2024_campaign": 0, "productions_with_support": 0})
    results.append(check("partial (1 production, wrong campaign)", r, expect_passed=False,
                          expect_score_min=1, expect_score_max=59))

    # Partial: 3 productions but only 1 activity type, no parcels — 30+25+5+0=60, threshold 75
    r = run_verifier(fn, {"new_productions_count": 3, "distinct_activities_count": 1,
                          "productions_in_2024_campaign": 3, "productions_with_support": 0})
    results.append(check("partial (3 prod, 1 activity, no parcels)", r, expect_passed=False,
                          expect_score_min=55, expect_score_max=74))

    # Full: 3 productions, 2024 campaign, 2 activities, all with parcels
    r = run_verifier(fn, {"new_productions_count": 3, "distinct_activities_count": 2,
                          "productions_in_2024_campaign": 3, "productions_with_support": 3})
    results.append(check("full completion", r, expect_passed=True, expect_score_min=60))

    return all(results)


# ─────────────────────────────────────────────────────────────────────────────
# Task 2: herd_exit_batch_processing
# ─────────────────────────────────────────────────────────────────────────────
def test_herd_exit():
    print("\n[herd_exit_batch_processing]")
    fn = load_verifier("herd_exit_batch_processing")
    results = []

    # Do-nothing
    r = run_verifier(fn, {"animals_exited_after_start": 0, "exits_on_target_date_2024_03_01": 0,
                          "oldest_animals_exited": 0, "new_sale_invoices": 0})
    results.append(check("do-nothing", r, expect_passed=False, expect_score_max=0))

    # Partial: 3 exits recorded, wrong date, no invoice
    r = run_verifier(fn, {"animals_exited_after_start": 3, "exits_on_target_date_2024_03_01": 0,
                          "oldest_animals_exited": 2, "new_sale_invoices": 0})
    results.append(check("partial (3 exits, wrong date, no invoice)", r, expect_passed=False,
                          expect_score_min=1, expect_score_max=59))

    # Near-complete: 5 exits, right date, no invoice — 30+25+0+10=65, threshold 70
    r = run_verifier(fn, {"animals_exited_after_start": 5, "exits_on_target_date_2024_03_01": 5,
                          "oldest_animals_exited": 4, "new_sale_invoices": 0})
    results.append(check("near-complete (no invoice)", r, expect_passed=False,
                          expect_score_min=55, expect_score_max=69))

    # Full completion
    r = run_verifier(fn, {"animals_exited_after_start": 5, "exits_on_target_date_2024_03_01": 5,
                          "oldest_animals_exited": 5, "new_sale_invoices": 1})
    results.append(check("full completion", r, expect_passed=True, expect_score_min=60))

    return all(results)


# ─────────────────────────────────────────────────────────────────────────────
# Task 3: purchase_invoice_multi_supplier_entry
# ─────────────────────────────────────────────────────────────────────────────
def test_purchase_invoices():
    print("\n[purchase_invoice_multi_supplier_entry]")
    fn = load_verifier("purchase_invoice_multi_supplier_entry")
    results = []

    # Do-nothing
    r = run_verifier(fn, {"new_purchase_invoices": 0, "distinct_suppliers": 0,
                          "validated_invoices": 0, "invoices_dated_correctly": 0})
    results.append(check("do-nothing", r, expect_passed=False, expect_score_max=0))

    # Wrong-target: invoices but all from same supplier
    r = run_verifier(fn, {"new_purchase_invoices": 3, "distinct_suppliers": 1,
                          "validated_invoices": 0, "invoices_dated_correctly": 3})
    results.append(check("wrong-target (1 supplier)", r, expect_passed=False, expect_score_max=0))

    # Partial: 2 invoices from 2 suppliers, 1 validated, right date
    r = run_verifier(fn, {"new_purchase_invoices": 2, "distinct_suppliers": 2,
                          "validated_invoices": 1, "invoices_dated_correctly": 2})
    results.append(check("partial (2 inv, 2 suppliers, 1 validated)", r, expect_passed=False,
                          expect_score_min=1, expect_score_max=59))

    # Full completion
    r = run_verifier(fn, {"new_purchase_invoices": 3, "distinct_suppliers": 3,
                          "validated_invoices": 2, "invoices_dated_correctly": 3})
    results.append(check("full completion", r, expect_passed=True, expect_score_min=60))

    return all(results)


# ─────────────────────────────────────────────────────────────────────────────
# Task 4: phytosanitary_spray_campaign
# ─────────────────────────────────────────────────────────────────────────────
def test_spray_campaign():
    print("\n[phytosanitary_spray_campaign]")
    fn = load_verifier("phytosanitary_spray_campaign")
    results = []

    # Do-nothing
    r = run_verifier(fn, {"all_new_interventions": 0, "new_spraying_interventions": 0,
                          "interventions_dated_2023_06_15": 0, "interventions_with_parameters": 0,
                          "procedure_names_used": ""})
    results.append(check("do-nothing", r, expect_passed=False, expect_score_max=0))

    # Partial: 2 interventions but wrong procedure name and no date
    r = run_verifier(fn, {"all_new_interventions": 2, "new_spraying_interventions": 0,
                          "interventions_dated_2023_06_15": 0, "interventions_with_parameters": 1,
                          "procedure_names_used": "fertilisation"})
    results.append(check("partial (2 non-spray interventions)", r, expect_passed=False,
                          expect_score_min=1, expect_score_max=59))

    # Near-complete: 3 spray interventions, right date, but no parameters
    r = run_verifier(fn, {"all_new_interventions": 3, "new_spraying_interventions": 3,
                          "interventions_dated_2023_06_15": 3, "interventions_with_parameters": 0,
                          "procedure_names_used": "pulverisation"})
    results.append(check("near-complete (no parameters)", r, expect_passed=True,
                          expect_score_min=60))

    # Full completion
    r = run_verifier(fn, {"all_new_interventions": 3, "new_spraying_interventions": 3,
                          "interventions_dated_2023_06_15": 3, "interventions_with_parameters": 3,
                          "procedure_names_used": "pulverisation"})
    results.append(check("full completion", r, expect_passed=True, expect_score_min=60))

    return all(results)


# ─────────────────────────────────────────────────────────────────────────────
# Task 5: new_supplier_onboarding_with_first_order
# ─────────────────────────────────────────────────────────────────────────────
def test_supplier_onboarding():
    print("\n[new_supplier_onboarding_with_first_order]")
    fn = load_verifier("new_supplier_onboarding_with_first_order")
    results = []

    # Do-nothing
    r = run_verifier(fn, {"new_supplier_found": False, "supplier_has_supplier_role": False,
                          "supplier_postal_code_correct": False, "new_variant_count": 0,
                          "euclide_variant_found": False, "cervoise_variant_found": False,
                          "new_invoice_count": 0, "invoice_from_new_supplier": 0,
                          "invoice_amount_gte_7000": False, "invoice_validated": False,
                          "invoice_line_count": 0})
    results.append(check("do-nothing", r, expect_passed=False, expect_score_max=0))

    # Wrong-target: supplier not found (should be caught as mandatory)
    # (same as do-nothing since supplier_found=False)

    # Partial: supplier created with role, no variants, no invoice
    r = run_verifier(fn, {"new_supplier_found": True, "supplier_has_supplier_role": True,
                          "supplier_postal_code_correct": True, "new_variant_count": 0,
                          "euclide_variant_found": False, "cervoise_variant_found": False,
                          "new_invoice_count": 0, "invoice_from_new_supplier": 0,
                          "invoice_amount_gte_7000": False, "invoice_validated": False,
                          "invoice_line_count": 0})
    results.append(check("partial (supplier only, no variants, no invoice)", r,
                          expect_passed=False, expect_score_min=1, expect_score_max=59))

    # Partial: supplier + both variants, but no invoice
    r = run_verifier(fn, {"new_supplier_found": True, "supplier_has_supplier_role": True,
                          "supplier_postal_code_correct": True, "new_variant_count": 2,
                          "euclide_variant_found": True, "cervoise_variant_found": True,
                          "new_invoice_count": 0, "invoice_from_new_supplier": 0,
                          "invoice_amount_gte_7000": False, "invoice_validated": False,
                          "invoice_line_count": 0})
    results.append(check("partial (supplier+variants, no invoice)", r,
                          expect_passed=False, expect_score_min=30, expect_score_max=59))

    # Full completion
    r = run_verifier(fn, {"new_supplier_found": True, "supplier_has_supplier_role": True,
                          "supplier_postal_code_correct": True, "new_variant_count": 2,
                          "euclide_variant_found": True, "cervoise_variant_found": True,
                          "new_invoice_count": 1, "invoice_from_new_supplier": 1,
                          "invoice_amount_gte_7000": True, "invoice_validated": True,
                          "invoice_line_count": 2})
    results.append(check("full completion", r, expect_passed=True, expect_score_min=60))

    return all(results)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    tests = [
        test_crop_rotation,
        test_herd_exit,
        test_purchase_invoices,
        test_spray_campaign,
        test_supplier_onboarding,
    ]

    all_passed = True
    for test_fn in tests:
        ok = test_fn()
        all_passed = all_passed and ok

    print("\n" + "=" * 60)
    if all_passed:
        print(f"[{PASS}] All verifier tests passed")
    else:
        print(f"[{FAIL}] Some verifier tests FAILED")
    print("=" * 60)
    sys.exit(0 if all_passed else 1)
