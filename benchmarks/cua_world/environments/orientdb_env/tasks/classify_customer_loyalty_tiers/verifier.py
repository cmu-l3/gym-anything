#!/usr/bin/env python3
"""Verifier for classify_customer_loyalty_tiers."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/classify_customer_loyalty_tiers_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


def _has_unique_email_index(indexes):
    for idx in indexes or []:
        if (idx.get("type") or "").upper() != "UNIQUE":
            continue
        if idx.get("name") == "LoyaltyTier.CustomerEmail":
            return True
        fields = idx.get("fields") or []
        if len(fields) == 1 and fields[0] == "CustomerEmail":
            return True
    return False


def verify_classify_customer_loyalty_tiers(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_tiers = metadata.get("expected_tiers", {})

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"could not load result: {exc}"}

    # Wrong-target rejection: any email outside expected cohort
    unexpected = result.get("unexpected_emails", [])
    if unexpected:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Off-target LoyaltyTier rows for email(s): {unexpected}",
        }

    score = 0
    feedback = []

    # Criterion 1: Schema shape — LoyaltyTier exists with all 4 mandatory properties (20 pts)
    req_props = {"CustomerEmail", "Tier", "TotalSpend", "CompletedOrderCount"}
    props = set(result.get("loyalty_tier_properties", []))
    mandatory = result.get("loyalty_tier_mandatory", {})
    schema_ok = (
        result.get("loyalty_tier_exists")
        and req_props.issubset(props)
        and all(mandatory.get(p, False) for p in req_props)
    )
    if schema_ok:
        score += 20
        feedback.append("LoyaltyTier schema is correct with all mandatory properties")
    else:
        feedback.append(f"LoyaltyTier schema incomplete; found props={sorted(props)}, mandatory={mandatory}")

    # Criterion 2: UNIQUE index on CustomerEmail (15 pts)
    if _has_unique_email_index(result.get("loyalty_tier_indexes", [])):
        score += 15
        feedback.append("LoyaltyTier.CustomerEmail UNIQUE index present")
    else:
        feedback.append("LoyaltyTier.CustomerEmail UNIQUE index missing")

    # Criterion 3: Tier assignment correctness (40 pts — 10 per profile)
    tier_rows = result.get("tier_rows", {})
    tier_pts = 0
    tier_feedback = []
    for email, exp in expected_tiers.items():
        actual = tier_rows.get(email, {})
        if actual.get("Tier") == exp.get("Tier"):
            tier_pts += 10
        else:
            tier_feedback.append(f"{email}: expected Tier={exp['Tier']}, got {actual.get('Tier')!r}")
    score += tier_pts
    if tier_pts == 40:
        feedback.append("All 4 loyalty tier assignments are correct")
    else:
        feedback.append(f"Tier mismatches: {tier_feedback}")

    # Criterion 4: TotalSpend accuracy within ±0.01 (15 pts — 3.75 per profile, rounded)
    spend_pts = 0
    spend_feedback = []
    for email, exp in expected_tiers.items():
        actual = tier_rows.get(email, {})
        exp_spend = float(exp.get("TotalSpend", 0))
        act_spend = float(actual.get("TotalSpend", -1) or -1)
        if abs(act_spend - exp_spend) <= 0.01:
            spend_pts += 1
    total_spend_score = spend_pts * 3  # up to 12; grant remaining 3 if all 4 correct
    if spend_pts == 4:
        total_spend_score = 15
        feedback.append("TotalSpend values are correct for all profiles")
    elif spend_pts >= 2:
        feedback.append(f"TotalSpend correct for {spend_pts}/4 profiles")
    else:
        feedback.append("TotalSpend values are mostly incorrect")
    score += total_spend_score

    # Criterion 5: Baseline delta proves new work (10 pts)
    baseline_count = int(result.get("baseline_tier_count", 0) or 0)
    if len(tier_rows) > baseline_count and len(tier_rows) >= len(expected_tiers):
        score += 10
        feedback.append("LoyaltyTier rows increased from baseline")
    else:
        feedback.append("Baseline delta check failed — no new rows detected")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
