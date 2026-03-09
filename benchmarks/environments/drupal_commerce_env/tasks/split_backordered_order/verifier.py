#!/usr/bin/env python3
"""Verifier for split_backordered_order."""

import json
import os
import tempfile


def verify_split_backordered_order(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/split_backordered_order_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {exc}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    metadata = task_info.get("metadata", {})
    in_stock_skus = {sku.upper() for sku in metadata.get("in_stock_skus", [])}
    backordered_sku = str(metadata.get("backordered_sku", "")).upper()

    score = 0
    feedback = []

    original_id = result.get("original_order_id")
    split_id = result.get("split_order_id")
    original_state = str(result.get("original_order_state", "")).lower()
    split_state = str(result.get("split_order_state", "")).lower()
    original_skus = {str(s).upper() for s in result.get("original_order_skus", [])}
    split_skus = {str(s).upper() for s in result.get("split_order_skus", [])}

    if original_id and result.get("modified_during_task"):
        score += 15
        feedback.append(f"Original order {original_id} was modified during the task.")
    else:
        feedback.append("Original order was not modified during the task.")

    if original_id and original_state and original_state != "draft":
        score += 20
        feedback.append(f"Original order moved out of draft ({original_state}).")
    else:
        feedback.append("Original order is still draft.")

    if in_stock_skus.issubset(original_skus):
        score += 20
        feedback.append("Placed order contains the in-stock SKUs.")
    else:
        missing = sorted(in_stock_skus - original_skus)
        feedback.append(f"Placed order missing in-stock SKUs: {missing}.")

    if backordered_sku and backordered_sku not in original_skus:
        score += 10
        feedback.append("Placed order excludes the backordered item.")
    else:
        feedback.append("Placed order still contains the backordered item.")

    if split_id:
        score += 10
        feedback.append(f"Split order {split_id} exists.")
    else:
        feedback.append("No split order was created.")

    if split_id and split_state == "draft":
        score += 10
        feedback.append("Split order remains in draft state.")
    else:
        feedback.append(f"Split order state is '{split_state}' (expected draft).")

    if split_skus == ({backordered_sku} if backordered_sku else split_skus):
        score += 15
        feedback.append("Split order contains only the backordered item.")
    else:
        feedback.append(f"Split order SKUs are {sorted(split_skus)} (expected only {backordered_sku}).")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " ".join(feedback)}
