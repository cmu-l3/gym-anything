#!/usr/bin/env python3
"""Verifier for corporate_rebranding_policy_rollout task.

Scoring breakdown (100 points):
  C1: Site Name = "Global Retail Assets" (15 pts)
  C2: Default Currency = "GBP" (15 pts)
  C3: Support Email = "it-support@globalretail.com" (15 pts)
  C4: Header Color = "#0055A4" (15 pts)
  C5: Laptops category policies updated (15 pts)
  C6: Tablets category policies updated (15 pts)
  C7: Desktops category left unchanged (10 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/corporate_rebranding_result.json"


def verify_corporate_rebranding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    settings = result.get("settings", {})
    categories = result.get("categories", {})

    # Expected values
    metadata = task_info.get("metadata", {})
    exp_site_name = metadata.get("expected_site_name", "Global Retail Assets")
    exp_currency = metadata.get("expected_currency", "GBP")
    exp_email = metadata.get("expected_email", "it-support@globalretail.com")
    exp_color = metadata.get("expected_color", "#0055A4").upper()

    # --- Do-Nothing Gate ---
    # Baseline checks: Snipe-IT Asset Management, USD, 0 flags
    changed = False
    if settings.get("site_name", "") != "Snipe-IT Asset Management": changed = True
    if settings.get("currency", "") != "USD": changed = True
    if settings.get("email", ""): changed = True
    if categories.get("laptops", {}).get("require_acceptance") == "1": changed = True
    
    if not changed:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No settings or category policies were changed."}

    # --- C1: Site Name (15 pts) ---
    actual_site_name = settings.get("site_name", "")
    if actual_site_name == exp_site_name:
        score += 15
        feedback.append("C1: Site Name correctly updated to 'Global Retail Assets' (+15)")
    else:
        feedback.append(f"C1: Site Name is '{actual_site_name}', expected '{exp_site_name}' (+0)")

    # --- C2: Currency (15 pts) ---
    actual_currency = settings.get("currency", "")
    if actual_currency.upper() == exp_currency.upper():
        score += 15
        feedback.append(f"C2: Default Currency correctly updated to '{exp_currency}' (+15)")
    else:
        feedback.append(f"C2: Default Currency is '{actual_currency}', expected '{exp_currency}' (+0)")

    # --- C3: Support Email (15 pts) ---
    actual_email = settings.get("email", "")
    if actual_email.lower() == exp_email.lower():
        score += 15
        feedback.append(f"C3: Support Email correctly updated to '{exp_email}' (+15)")
    else:
        feedback.append(f"C3: Support Email is '{actual_email}', expected '{exp_email}' (+0)")

    # --- C4: Header Color (15 pts) ---
    actual_color = settings.get("color", "").upper()
    # Accept with or without the hash symbol
    if actual_color in [exp_color, exp_color.replace("#", "")]:
        score += 15
        feedback.append(f"C4: Header Color correctly updated to '{exp_color}' (+15)")
    else:
        feedback.append(f"C4: Header Color is '{actual_color}', expected '{exp_color}' (+0)")

    # --- C5: Laptops Policy (15 pts) ---
    laptops = categories.get("laptops", {})
    l_acc = laptops.get("require_acceptance")
    l_email = laptops.get("checkin_email")
    if l_acc == "1" and l_email == "1":
        score += 15
        feedback.append("C5: Laptops category policies (acceptance & email) successfully enabled (+15)")
    else:
        feedback.append(f"C5: Laptops category incomplete. Acceptance={l_acc}, Email={l_email} (expected both 1) (+0)")

    # --- C6: Tablets Policy (15 pts) ---
    tablets = categories.get("tablets", {})
    t_acc = tablets.get("require_acceptance")
    t_email = tablets.get("checkin_email")
    if t_acc == "1" and t_email == "1":
        score += 15
        feedback.append("C6: Tablets category policies (acceptance & email) successfully enabled (+15)")
    else:
        feedback.append(f"C6: Tablets category incomplete. Acceptance={t_acc}, Email={t_email} (expected both 1) (+0)")

    # --- C7: Desktops Control Check (10 pts) ---
    desktops = categories.get("desktops", {})
    d_acc = desktops.get("require_acceptance")
    d_email = desktops.get("checkin_email")
    if d_acc == "0" and d_email == "0":
        score += 10
        feedback.append("C7: Desktops category successfully left unchanged (+10)")
    else:
        feedback.append(f"C7: Desktops category wrongly modified. Acceptance={d_acc}, Email={d_email} (expected both 0) (+0)")

    # Decide pass/fail
    # Threshold is 75 points. Must have done both branding and category work to pass.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "score": score,
            "settings": settings,
            "categories": categories
        }
    }