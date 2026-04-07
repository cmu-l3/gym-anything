#!/usr/bin/env python3
"""
Verifier for grand_opening_day_operations task.

The agent must complete a full store grand opening workflow:
1. Configure TX Sales Tax at 8.25%
2. Configure receipt header/footer for Riverside Electronics
3. Import 15 products from store_inventory.csv
4. Add customer Jordan Hayes (TechStart Inc.)
5. Process 4 sales (3 completed + 1 voided), including a coupon
6. Export Sales Report to daily_sales_report.csv
7. Write opening_day_summary.txt with store metrics

Scoring (100 points total):
  - daily_sales_report.csv exists and new (15 pts)
  - opening_day_summary.txt exists and new (10 pts)
  - Summary contains store name "Riverside Electronics" (10 pts)
  - Summary contains tax rate "8.25" (10 pts)
  - Summary contains item count ~15 (10 pts)
  - Summary contains completed sales count 3 (10 pts)
  - Summary contains voided sales count 1 (10 pts)
  - Summary contains revenue ~$452.95 (15 pts)
  - Copper data was modified during task (5 pts)
  - Tax configured in registry (5 pts)

Pass threshold: >= 60 AND both output files exist and are new
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\grand_opening_result.json"

EXPECTED_REVENUE = 452.95
REVENUE_TOLERANCE = 5.0


def verify_grand_opening_day_operations(traj, env_info, task_info):
    """
    Verify grand opening day operations task.

    Reads result JSON produced by export_result.ps1.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result JSON from container
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {json.dumps(result, indent=2)}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file. Export may have failed: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    # Quick gate: at least one output file must exist and be new
    report_exists = result.get('sales_report_exists', False)
    report_new = result.get('sales_report_new', False)
    summary_exists = result.get('summary_exists', False)
    summary_new = result.get('summary_new', False)

    any_output = (report_exists and report_new) or (summary_exists and summary_new)
    if not any_output:
        return {"passed": False, "score": 0,
                "feedback": (
                    "No output files found. Agent must create: "
                    "daily_sales_report.csv and opening_day_summary.txt "
                    "on the Desktop."
                )}

    # Scoring
    score = 0
    feedback_parts = []

    # 1. daily_sales_report.csv exists and new (15 pts)
    if report_exists and report_new:
        score += 15
        feedback_parts.append("daily_sales_report.csv created successfully.")
    elif report_exists and not report_new:
        feedback_parts.append("daily_sales_report.csv exists but is stale.")
    else:
        feedback_parts.append("daily_sales_report.csv not found.")

    # 2. opening_day_summary.txt exists and new (10 pts)
    if summary_exists and summary_new:
        score += 10
        feedback_parts.append(f"opening_day_summary.txt created ({result.get('summary_size', 0)} bytes).")
    elif summary_exists and not summary_new:
        feedback_parts.append("opening_day_summary.txt exists but is stale.")
    else:
        feedback_parts.append("opening_day_summary.txt not found.")

    # 3. Store name (10 pts)
    if result.get('has_store_name', False):
        score += 10
        feedback_parts.append("Store name 'Riverside Electronics' found in summary.")
    else:
        feedback_parts.append("Store name not found in summary.")

    # 4. Tax rate (10 pts)
    if result.get('has_tax_rate', False):
        score += 10
        feedback_parts.append("Tax rate 8.25% found in summary.")
    else:
        feedback_parts.append("Tax rate 8.25% not found in summary.")

    # 5. Item count (10 pts)
    if result.get('has_item_count', False):
        item_count = result.get('item_count_found')
        score += 10
        feedback_parts.append(f"Item count found: {item_count}.")
    else:
        feedback_parts.append("Item count not found in summary.")

    # 6. Completed sales count (10 pts)
    if result.get('has_completed', False):
        score += 10
        feedback_parts.append("Completed sales count (3) found in summary.")
    else:
        feedback_parts.append("Completed sales count not found in summary.")

    # 7. Voided sales count (10 pts)
    if result.get('has_voided', False):
        score += 10
        feedback_parts.append("Voided sales count (1) found in summary.")
    else:
        feedback_parts.append("Voided sales count not found in summary.")

    # 8. Revenue (15 pts)
    revenue_found = result.get('revenue_found')
    if result.get('has_revenue', False):
        score += 15
        feedback_parts.append(
            f"Revenue found: ${revenue_found:.2f if revenue_found else 'N/A'} "
            f"(expected ~${EXPECTED_REVENUE:.2f})."
        )
    else:
        feedback_parts.append(
            f"Revenue ~${EXPECTED_REVENUE:.2f} not found in summary."
        )

    # 9. Data modified (5 pts)
    if result.get('data_modified', False):
        score += 5
        feedback_parts.append("Copper data was modified during task.")
    else:
        feedback_parts.append("No Copper data modifications detected.")

    # 10. Tax configured in registry (5 pts)
    if result.get('tax_configured', False):
        score += 5
        feedback_parts.append("Tax rate found in Copper registry.")
    else:
        feedback_parts.append("Tax rate not found in Copper registry.")

    score = min(score, 100)

    # Pass requires >= 60 AND both output files present and new
    all_files_new = (report_exists and report_new) and (summary_exists and summary_new)
    passed = score >= 60 and all_files_new

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
