#!/usr/bin/env python3
"""Verifier for create_custom_price_order."""

import json
import os
import tempfile


def _load_result(copy_from_env):
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/create_custom_price_order_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            return json.load(f)
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)


def _find_item(items, sku):
    for item in items:
        if str(item.get("sku", "")).strip().upper() == sku.upper():
            return item
    return None


def _price_matches(value, expected):
    try:
        return abs(float(value) - float(expected)) <= 0.01
    except Exception:
        return False


def verify_create_custom_price_order(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result = _load_result(copy_from_env)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {exc}"}

    metadata = task_info.get("metadata", {})
    discounted_sku = metadata.get("discounted_sku", "SAMSUNG-BUDS2")
    regular_sku = metadata.get("regular_sku", "LOGI-MXM3S")
    discounted_price = metadata.get("discounted_price", "120.00")
    regular_price = metadata.get("regular_price", "99.99")

    score = 0
    feedback = []

    order_id = result.get("order_id")
    order_state = str(result.get("order_state", "")).strip().lower()
    items = result.get("items", [])

    if order_id:
        score += 10
        feedback.append(f"Order {order_id} exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "No order for mikewilson was created."}

    if result.get("modified_during_task"):
        score += 10
        feedback.append("Order was modified during the task session.")
    else:
        feedback.append("Order timestamp did not change during the task session.")

    if order_state and order_state != "draft":
        score += 20
        feedback.append(f"Order placed successfully (state={order_state}).")
    else:
        feedback.append("Order is still in draft state.")

    if len(items) == 2:
        score += 10
        feedback.append("Order contains exactly two line items.")
    else:
        feedback.append(f"Order contains {len(items)} line items (expected 2).")

    discounted_item = _find_item(items, discounted_sku)
    regular_item = _find_item(items, regular_sku)

    if discounted_item:
        score += 10
        feedback.append(f"Discounted item {discounted_sku} present.")
        if _price_matches(discounted_item.get("unit_price"), discounted_price):
            score += 20
            feedback.append(f"Discounted price set to {discounted_price}.")
        else:
            feedback.append(
                f"Discounted item price is {discounted_item.get('unit_price')} (expected {discounted_price})."
            )
    else:
        feedback.append(f"Discounted item {discounted_sku} missing.")

    if regular_item:
        score += 10
        feedback.append(f"Regular item {regular_sku} present.")
        if _price_matches(regular_item.get("unit_price"), regular_price):
            score += 10
            feedback.append(f"Regular item price preserved at {regular_price}.")
        else:
            feedback.append(
                f"Regular item price is {regular_item.get('unit_price')} (expected {regular_price})."
            )
    else:
        feedback.append(f"Regular item {regular_sku} missing.")

    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " ".join(feedback)}
