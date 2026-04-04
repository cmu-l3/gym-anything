#!/usr/bin/env python3
"""
Verifier for purchase_invoice_multi_supplier_entry task.

The agent must create 3 purchase invoices from 3 distinct suppliers,
validate at least 2, all dated 2024-01-20.

Scoring (100 points):
- 30 pts: >=3 new purchase invoices created after task start
- 30 pts: >=3 distinct suppliers used across invoices
- 25 pts: >=2 invoices in validated/confirmed state
- 15 pts: All invoices dated 2024-01-20

Pass threshold: 60 points
Mandatory: >=2 new purchase invoices from distinct suppliers
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/purchase_entry_result.json"


def verify_purchase_invoice_multi_supplier_entry(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback_parts = []
    subscores = {}

    new_invoices = int(result.get("new_purchase_invoices", 0))
    distinct_suppliers = int(result.get("distinct_suppliers", 0))
    validated = int(result.get("validated_invoices", 0))
    dated_correctly = int(result.get("invoices_dated_correctly", 0))

    # --- Mandatory check ---
    if new_invoices < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No purchase invoices created — task not attempted",
        }
    if distinct_suppliers < 2:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Only {distinct_suppliers} distinct supplier(s) used — need at least 2 different suppliers",
        }

    # --- Criterion 1: >=3 new purchase invoices (30 pts) ---
    if new_invoices >= 3:
        score += 30
        subscores["min_3_invoices"] = True
        feedback_parts.append(f"{new_invoices} purchase invoices created (>=3 required)")
    elif new_invoices == 2:
        score += 15
        subscores["min_3_invoices"] = False
        feedback_parts.append(f"Only {new_invoices} invoices (3 required)")
    else:
        score += 5
        subscores["min_3_invoices"] = False
        feedback_parts.append(f"Only {new_invoices} invoice created")

    # --- Criterion 2: >=3 distinct suppliers (30 pts) ---
    if distinct_suppliers >= 3:
        score += 30
        subscores["distinct_suppliers"] = True
        feedback_parts.append(f"{distinct_suppliers} distinct suppliers used (diversification confirmed)")
    elif distinct_suppliers == 2:
        score += 15
        subscores["distinct_suppliers"] = False
        feedback_parts.append(f"Only {distinct_suppliers} distinct suppliers (3 required)")
    else:
        subscores["distinct_suppliers"] = False
        feedback_parts.append("Only 1 supplier used")

    # --- Criterion 3: >=2 validated invoices (25 pts) ---
    if validated >= 2:
        score += 25
        subscores["invoices_validated"] = True
        feedback_parts.append(f"{validated} invoices validated/confirmed (accounting entries generated)")
    elif validated == 1:
        score += 10
        subscores["invoices_validated"] = False
        feedback_parts.append(f"Only {validated} invoice validated")
    else:
        subscores["invoices_validated"] = False
        feedback_parts.append("No invoices validated/confirmed")

    # --- Criterion 4: Correct date 2024-01-20 (15 pts) ---
    if dated_correctly >= 3:
        score += 15
        subscores["correct_date"] = True
        feedback_parts.append("All invoices correctly dated 2024-01-20")
    elif dated_correctly >= 1:
        score += 7
        subscores["correct_date"] = False
        feedback_parts.append(f"Only {dated_correctly}/{new_invoices} invoices dated 2024-01-20")
    else:
        subscores["correct_date"] = False
        feedback_parts.append("No invoices dated 2024-01-20")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
