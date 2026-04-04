#!/usr/bin/env python3
"""
Verifier for new_store_configuration task.

The agent must configure Copper POS for a new store:
1. Set Business Name to 'Meridian Goods & Supply'
2. Configure receipt header/footer/date-time
3. Set default tax rate to 8.00%
4. Add 4 custom categories with correct tax rates
5. Ensure Check payment method is available
6. Process a test transaction and write tax_verification.txt
   with the correct: Tax Amount = $4.80, Total = $64.80

Scoring (100 points total):
  - tax_verification.txt exists and is new (20 pts)
  - Business name "Meridian" found in verification file (20 pts)
  - Tax rate 8% mentioned in verification file (20 pts)
  - Correct tax amount $4.80 found (20 pts)
  - Correct total $64.80 found (20 pts)

Pass threshold: >= 60 points AND tax_verification.txt exists and is new
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\new_store_config_result.json"

EXPECTED_TAX_AMOUNT = 4.80
EXPECTED_TOTAL = 64.80


def verify_new_store_configuration(traj, env_info, task_info):
    """
    Verify new store configuration task.

    Reads result JSON produced by export_result.ps1, which contains:
      - tax_verify_exists: bool
      - tax_verify_new: bool
      - file_size: int
      - has_biz_name: bool
      - has_tax_rate: bool
      - has_tax_amount: bool
      - tax_amount_found: float or null
      - has_total: bool
      - total_found: float or null
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

    verify_exists = result.get('tax_verify_exists', False)
    verify_new = result.get('tax_verify_new', False)

    # Criterion 1: Verification file exists and is new (20 pts)
    if verify_exists and verify_new:
        score += 20
        file_size = result.get('file_size', 0)
        feedback_parts.append(f"tax_verification.txt created ({file_size} bytes).")
    elif verify_exists and not verify_new:
        feedback_parts.append("tax_verification.txt exists but predates task start (stale file).")
        return {"passed": False, "score": 0,
                "feedback": "tax_verification.txt exists but was not created during this task."}
    else:
        feedback_parts.append("tax_verification.txt not found on Desktop.")
        return {"passed": False, "score": 0,
                "feedback": (
                    "No tax_verification.txt found. Agent must configure the store, process a test "
                    "transaction with 'Varsity Top Test' at $60.00 (8% tax), and write the result to "
                    "C:\\Users\\Docker\\Desktop\\tax_verification.txt."
                )}

    # Criterion 2: Business name "Meridian" in verification file (20 pts)
    if result.get('has_biz_name', False):
        score += 20
        feedback_parts.append("Business name 'Meridian Goods & Supply' found in verification file.")
    else:
        feedback_parts.append(
            "Business name 'Meridian' not found in tax_verification.txt. "
            "Check that Business Name is set correctly in Copper settings."
        )

    # Criterion 3: Tax rate 8% mentioned (20 pts)
    if result.get('has_tax_rate', False):
        score += 20
        feedback_parts.append("Tax rate 8.00% confirmed in verification file.")
    else:
        feedback_parts.append(
            "Tax rate 8.00% not found in tax_verification.txt. "
            "Ensure default tax rate is set to 8.00% before processing the test transaction."
        )

    # Criterion 4: Correct tax amount $4.80 (20 pts)
    tax_amount_found = result.get('tax_amount_found')
    if result.get('has_tax_amount', False):
        score += 20
        actual_tax_str = f"${tax_amount_found:.2f}" if tax_amount_found is not None else "N/A"
        feedback_parts.append(
            f"Correct tax amount ${EXPECTED_TAX_AMOUNT:.2f} found "
            f"(actual: {actual_tax_str})."
        )
    else:
        feedback_parts.append(
            f"Tax amount ${EXPECTED_TAX_AMOUNT:.2f} not found in verification file. "
            f"Expected: 8% of $60.00 = $4.80. Found: {tax_amount_found}"
        )

    # Criterion 5: Correct total $64.80 (20 pts)
    total_found = result.get('total_found')
    if result.get('has_total', False):
        score += 20
        actual_total_str = f"${total_found:.2f}" if total_found is not None else "N/A"
        feedback_parts.append(
            f"Correct total ${EXPECTED_TOTAL:.2f} found "
            f"(actual: {actual_total_str})."
        )
    else:
        feedback_parts.append(
            f"Total ${EXPECTED_TOTAL:.2f} not found in verification file. "
            f"Expected: $60.00 + $4.80 tax = $64.80. Found: {total_found}"
        )

    score = min(score, 100)
    # Require ≥80 pts — agents must confirm tax amount AND total, not just set biz name+rate
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
