#!/usr/bin/env python3
"""
Verifier for corporate_customer_onboarding task.

The agent must:
1. Import 30 existing customers from existing_customers.csv
2. Add 6 new corporate clients with company, contact, tier and credit limit in Notes
   - Pacific Northwest Distributors (GOLD, $25,000)
   - Midwest Retail Holdings (SILVER, $15,000)
   - Southern Fashion Group (GOLD, $30,000)
   - Great Lakes Supply Co. (BRONZE, $5,000)
   - Atlantic Coast Trading (SILVER, $12,000)
   - Mountain West Goods (BRONZE, $7,500)
3. Update Notes for 3 existing customers:
   - Sheryl Baxter: "Preferred Account: Yes"
   - Preston Lozano: "Preferred Account: Yes"
   - Roy Berry: "Preferred Account: No, Past Due Balance"
4. Export customer list to C:\\Users\\Docker\\Desktop\\customer_accounts.csv

Scoring (100 points total):
  - Export file exists and is new (15 pts)
  - Total rows >= 36 (existing 30 + 6 new) (15 pts)
  - Corporate companies found in export (5 pts each × 6 = 30 pts)
  - Existing customers updated (5 pts each × 3 = 15 pts)
  - Has GOLD tier customers (5 pts)
  - Has SILVER tier customers (5 pts)
  - Has BRONZE tier customers (5 pts)
  - Has credit limit information (10 pts)

Pass threshold: >= 60 points AND export file exists and is new
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\corporate_onboarding_result.json"
MIN_EXPECTED_CUSTOMERS = 36


def verify_corporate_customer_onboarding(traj, env_info, task_info):
    """
    Verify corporate customer onboarding task.

    Reads result JSON produced by export_result.ps1, which contains:
      - export_file_exists: bool
      - export_file_new: bool
      - total_rows: int
      - companies_found_count: int  (out of 6)
      - updates_found_count: int    (out of 3)
      - has_gold_tier: bool
      - has_silver_tier: bool
      - has_bronze_tier: bool
      - has_credit_limit: bool
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # ----------------------------------------------------------------
    # Load result JSON from container
    # ----------------------------------------------------------------
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {result}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file. Export may have failed: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    # ----------------------------------------------------------------
    # Scoring
    # ----------------------------------------------------------------
    score = 0
    feedback_parts = []

    export_exists = result.get('export_file_exists', False)
    export_new = result.get('export_file_new', False)

    # Criterion 1: Export file exists and is new (15 pts)
    if export_exists and export_new:
        score += 15
        feedback_parts.append("customer_accounts.csv created successfully.")
    elif export_exists and not export_new:
        feedback_parts.append("customer_accounts.csv exists but predates task start (stale file).")
        return {"passed": False, "score": 0,
                "feedback": "customer_accounts.csv exists but was not created during this task."}
    else:
        feedback_parts.append("customer_accounts.csv not found on Desktop.")
        return {"passed": False, "score": 0,
                "feedback": "No export file found. Agent must export customer list to C:\\Users\\Docker\\Desktop\\customer_accounts.csv."}

    # Criterion 2: Total rows >= 36 (15 pts)
    total_rows = result.get('total_rows', 0)
    if total_rows >= MIN_EXPECTED_CUSTOMERS:
        score += 15
        feedback_parts.append(
            f"Export has {total_rows} customers (>= {MIN_EXPECTED_CUSTOMERS} expected: 30 existing + 6 new)."
        )
    elif total_rows >= 30:
        score += 8
        feedback_parts.append(
            f"Export has {total_rows} customers (some new corporate accounts may be missing)."
        )
    elif total_rows >= 6:
        score += 4
        feedback_parts.append(
            f"Export has only {total_rows} customers (expected >= {MIN_EXPECTED_CUSTOMERS})."
        )
    else:
        feedback_parts.append(f"Export has too few customers ({total_rows}). Expected >= {MIN_EXPECTED_CUSTOMERS}.")

    # Criterion 3: Corporate companies found (5 pts each × 6 = 30 pts)
    companies_found = result.get('companies_found_count', 0)
    companies_pts = companies_found * 5
    score += companies_pts
    feedback_parts.append(
        f"Corporate accounts found: {companies_found}/6 ({companies_pts}/30 pts). "
        "Expected: Pacific Northwest Distributors, Midwest Retail Holdings, Southern Fashion Group, "
        "Great Lakes Supply Co., Atlantic Coast Trading, Mountain West Goods."
    )

    # Criterion 4: Existing customer updates (5 pts each × 3 = 15 pts)
    updates_found = result.get('updates_found_count', 0)
    updates_pts = updates_found * 5
    score += updates_pts
    feedback_parts.append(
        f"Existing customer notes updated: {updates_found}/3 ({updates_pts}/15 pts). "
        "Expected updates: Sheryl Baxter, Preston Lozano, Roy Berry."
    )

    # Criterion 5: Has GOLD tier (5 pts)
    if result.get('has_gold_tier', False):
        score += 5
        feedback_parts.append("GOLD tier customers present in export.")
    else:
        feedback_parts.append("No GOLD tier customers found in export.")

    # Criterion 6: Has SILVER tier (5 pts)
    if result.get('has_silver_tier', False):
        score += 5
        feedback_parts.append("SILVER tier customers present in export.")
    else:
        feedback_parts.append("No SILVER tier customers found in export.")

    # Criterion 7: Has BRONZE tier (5 pts)
    if result.get('has_bronze_tier', False):
        score += 5
        feedback_parts.append("BRONZE tier customers present in export.")
    else:
        feedback_parts.append("No BRONZE tier customers found in export.")

    # Criterion 8: Has credit limit information (10 pts)
    if result.get('has_credit_limit', False):
        score += 10
        feedback_parts.append("Credit limit information present in export.")
    else:
        feedback_parts.append("No credit limit information found in export notes.")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
