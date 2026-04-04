#!/usr/bin/env python3
"""
Verifier for multi_report_sales_analytics task.

The agent must:
1. Import 15 items from electronics_clothing_inventory.csv
2. Process 3 transactions:
   - A: Anker PowerCore 10000 x2 + Apple Lightning Cable x1 = $71.97 (Cash)
   - B: Samsung Galaxy Buds FE x1 with 10% discount = $89.99 (Credit Card)
   - C: Ocean Blue Shirt x2 + Classic Varsity Top x1 = $160.00 (Cash)
3. Export Sales Report -> C:\\Users\\Docker\\Desktop\\weekly_sales.csv
4. Export Inventory/Stock Report -> C:\\Users\\Docker\\Desktop\\stock_levels.csv
5. Write analytics_summary.txt with:
   - Total Items in Inventory: 15
   - Transactions Processed Today: 3
   - Total Today Revenue: $321.96
   - Top Category Today: Electronics

Scoring (100 points total):
  - weekly_sales.csv exists and new (20 pts)
  - stock_levels.csv exists and new (20 pts)
  - analytics_summary.txt exists and new (15 pts)
  - Summary has item count info (10 pts)
  - Summary has transaction count info (5 pts)
  - Summary has correct total revenue ~$321.96 (20 pts)
  - Summary mentions Electronics category (5 pts)
  - weekly_sales has data rows (5 pts)

Pass threshold: >= 60 points AND all 3 output files exist and are new
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\multi_report_result.json"

EXPECTED_REVENUE = 321.96
REVENUE_TOLERANCE = 5.0  # allow ±$5 tolerance


def verify_multi_report_sales_analytics(traj, env_info, task_info):
    """
    Verify multi-report sales analytics task.

    Reads result JSON produced by export_result.ps1, which contains:
      - weekly_sales_exists: bool
      - weekly_sales_new: bool
      - stock_levels_exists: bool
      - stock_levels_new: bool
      - analytics_summary_exists: bool
      - analytics_summary_new: bool
      - summary_file_size: int
      - has_item_count: bool
      - item_count_found: int or null
      - has_transactions: bool
      - has_total_revenue: bool
      - revenue_found: float or null
      - has_electronics_cat: bool
      - sales_row_count: int
      - stock_row_count: int
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
    # Quick gate: at least one output file must exist and be new
    # ----------------------------------------------------------------
    ws_exists = result.get('weekly_sales_exists', False)
    ws_new = result.get('weekly_sales_new', False)
    sl_exists = result.get('stock_levels_exists', False)
    sl_new = result.get('stock_levels_new', False)
    as_exists = result.get('analytics_summary_exists', False)
    as_new = result.get('analytics_summary_new', False)

    any_output = (ws_exists and ws_new) or (sl_exists and sl_new) or (as_exists and as_new)
    if not any_output:
        return {"passed": False, "score": 0,
                "feedback": (
                    "No output files found. Agent must create: "
                    "weekly_sales.csv, stock_levels.csv, and analytics_summary.txt "
                    "on the Desktop."
                )}

    # ----------------------------------------------------------------
    # Scoring
    # ----------------------------------------------------------------
    score = 0
    feedback_parts = []

    # Criterion 1: weekly_sales.csv exists and new (20 pts)
    if ws_exists and ws_new:
        score += 20
        feedback_parts.append("weekly_sales.csv created successfully.")
    elif ws_exists and not ws_new:
        feedback_parts.append("weekly_sales.csv exists but is stale (predates task start).")
    else:
        feedback_parts.append("weekly_sales.csv not found.")

    # Criterion 2: stock_levels.csv exists and new (20 pts)
    if sl_exists and sl_new:
        score += 20
        feedback_parts.append("stock_levels.csv created successfully.")
    elif sl_exists and not sl_new:
        feedback_parts.append("stock_levels.csv exists but is stale (predates task start).")
    else:
        feedback_parts.append("stock_levels.csv not found.")

    # Criterion 3: analytics_summary.txt exists and new (15 pts)
    if as_exists and as_new:
        score += 15
        summary_size = result.get('summary_file_size', 0)
        feedback_parts.append(f"analytics_summary.txt created ({summary_size} bytes).")
    elif as_exists and not as_new:
        feedback_parts.append("analytics_summary.txt exists but is stale (predates task start).")
    else:
        feedback_parts.append("analytics_summary.txt not found.")

    # Criterion 4: Summary has item count information (10 pts)
    if result.get('has_item_count', False):
        item_count = result.get('item_count_found')
        score += 10
        feedback_parts.append(
            f"Item count found in analytics_summary.txt: {item_count} items."
        )
    else:
        feedback_parts.append(
            "Item count not found in analytics_summary.txt. "
            "Expected: 'Total Items in Inventory: 15'."
        )

    # Criterion 5: Summary has transaction count info (5 pts)
    if result.get('has_transactions', False):
        score += 5
        feedback_parts.append("Transaction count info found in analytics_summary.txt.")
    else:
        feedback_parts.append(
            "Transaction count not found in analytics_summary.txt. "
            "Expected: 'Transactions Processed Today: 3'."
        )

    # Criterion 6: Correct total revenue ~$321.96 (20 pts)
    revenue_found = result.get('revenue_found')
    if result.get('has_total_revenue', False):
        score += 20
        feedback_parts.append(
            f"Correct revenue found: ${revenue_found:.2f if revenue_found else 'N/A'} "
            f"(expected ~${EXPECTED_REVENUE:.2f})."
        )
    else:
        feedback_parts.append(
            f"Revenue ~${EXPECTED_REVENUE:.2f} not found in analytics_summary.txt. "
            f"Expected: Transaction A $71.97 + B $89.99 + C $160.00 = $321.96."
        )

    # Criterion 7: Mentions Electronics category (5 pts)
    if result.get('has_electronics_cat', False):
        score += 5
        feedback_parts.append("Electronics category mentioned as top category.")
    else:
        feedback_parts.append(
            "Electronics category not mentioned in summary. "
            "Expected: 'Top Category Today: Electronics'."
        )

    # Criterion 8: weekly_sales has data rows (5 pts)
    sales_rows = result.get('sales_row_count', 0)
    if sales_rows >= 2:  # header + at least 1 data row
        score += 5
        feedback_parts.append(f"weekly_sales.csv has {sales_rows} rows (including header).")
    else:
        feedback_parts.append(f"weekly_sales.csv has {sales_rows} rows (appears empty).")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
