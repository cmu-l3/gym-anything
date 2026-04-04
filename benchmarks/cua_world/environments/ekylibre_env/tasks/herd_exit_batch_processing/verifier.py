#!/usr/bin/env python3
"""
Verifier for herd_exit_batch_processing task.

The agent must:
1. Record exit for 5 oldest bovines (exit_at = 2024-03-01, reason = Abattage)
2. Create a consolidated sale invoice for the 5 animals

Scoring (100 points):
- 30 pts: >=5 animals have exit_at updated after task start
- 25 pts: Exit date is 2024-03-01 for >=5 animals
- 25 pts: >=1 new sale invoice created
- 20 pts: Animals exited are among the oldest (born before 2010)

Pass threshold: 60 points
Mandatory: >=5 animal exits recorded
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/herd_exit_result.json"


def verify_herd_exit_batch_processing(traj, env_info, task_info):
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

    exits_after = int(result.get("animals_exited_after_start", 0))
    exits_target_date = int(result.get("exits_on_target_date_2024_03_01", 0))
    oldest_exited = int(result.get("oldest_animals_exited", 0))
    new_sales = int(result.get("new_sale_invoices", 0))

    # --- Mandatory check ---
    if exits_after < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No animal exits recorded — task not attempted",
        }

    # --- Criterion 1: >=5 animal exits recorded (30 pts) ---
    if exits_after >= 5:
        score += 30
        subscores["min_5_exits"] = True
        feedback_parts.append(f"Recorded exit for {exits_after} animals (>=5 required)")
    elif exits_after >= 3:
        score += 15
        subscores["min_5_exits"] = False
        feedback_parts.append(f"Only {exits_after} animal exits recorded (5 required)")
    else:
        score += 5
        subscores["min_5_exits"] = False
        feedback_parts.append(f"Only {exits_after} animal exit recorded")

    # --- Criterion 2: Exit date is 2024-03-01 (25 pts) ---
    if exits_target_date >= 5:
        score += 25
        subscores["correct_exit_date"] = True
        feedback_parts.append(f"All {exits_target_date} exits dated 2024-03-01 (correct)")
    elif exits_target_date >= 1:
        score += 10
        subscores["correct_exit_date"] = False
        feedback_parts.append(f"{exits_target_date}/{exits_after} exits dated 2024-03-01")
    else:
        subscores["correct_exit_date"] = False
        feedback_parts.append("No exits recorded with date 2024-03-01")

    # --- Criterion 3: >=1 new sale invoice (25 pts) ---
    if new_sales >= 1:
        score += 25
        subscores["sale_invoice_created"] = True
        feedback_parts.append(f"{new_sales} sale invoice(s) created for the batch")
    else:
        subscores["sale_invoice_created"] = False
        feedback_parts.append("No sale invoice created for the exited animals")

    # --- Criterion 4: Oldest animals selected (20 pts) ---
    if oldest_exited >= 5:
        score += 20
        subscores["oldest_animals"] = True
        feedback_parts.append(f"All {oldest_exited} exited animals are among the oldest (born<2010)")
    elif oldest_exited >= 3:
        score += 10
        subscores["oldest_animals"] = False
        feedback_parts.append(f"Only {oldest_exited} of exited animals are among the oldest")
    elif oldest_exited >= 1:
        score += 5
        subscores["oldest_animals"] = False
        feedback_parts.append(f"Only {oldest_exited} exited animal(s) born before 2010")
    else:
        subscores["oldest_animals"] = False
        feedback_parts.append("Exited animals are not the oldest ones in the herd")

    # Require 70+ so that exits+date alone (55 pts) do not pass;
    # the sale invoice is a mandatory deliverable for this task.
    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
