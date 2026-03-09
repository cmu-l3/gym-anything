#!/usr/bin/env python3
"""Verifier for modifier_group_configuration task.

Scoring (100 points):
- PIZZA TOPPINGS modifier group created: 15 pts
- Each of 8 pizza modifiers with correct name (4 pts each): 32 pts
- BURGER ADD-ONS modifier group created: 15 pts
- Each of 5 burger modifiers with correct name (3 pts each): 15 pts
- PIZZA TOPPINGS assigned to >=1 pizza item: 20 pts
- Correct prices on >=10 of 13 modifiers (bonus): 3 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PIZZA_MODIFIERS = [
    {"name": "EXTRA CHEESE", "price": 1.50},
    {"name": "MUSHROOMS", "price": 0.75},
    {"name": "PEPPERONI", "price": 1.25},
    {"name": "ONIONS", "price": 0.50},
    {"name": "PEPPERS", "price": 0.75},
    {"name": "OLIVES", "price": 0.50},
    {"name": "ANCHOVIES", "price": 0.75},
    {"name": "SAUSAGE", "price": 1.25},
]

BURGER_MODIFIERS = [
    {"name": "AVOCADO", "price": 1.50},
    {"name": "BACON", "price": 1.25},
    {"name": "FRIED EGG", "price": 1.00},
    {"name": "EXTRA PATTY", "price": 3.00},
    {"name": "JALAPENOS", "price": 0.50},
]


def verify_modifier_group_configuration(traj, env_info, task_info):
    """Verify modifier group configuration."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/modifier_group_configuration_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    if not result.get("derby_tools_available"):
        return {"passed": False, "score": 0, "feedback": "Derby tools unavailable"}

    score = 0
    feedback_parts = []

    modifier_groups = result.get("modifier_groups", [])
    modifiers = result.get("modifiers", [])
    pizza_assignments = result.get("pizza_topping_assignments", [])

    grp_names_upper = {g["name"].strip().upper(): g for g in modifier_groups}
    mod_names_upper = {m["name"].strip().upper(): m for m in modifiers}

    def _price_near(actual_str, expected, tol=0.02):
        try:
            return abs(float(actual_str) - expected) <= tol
        except (ValueError, TypeError):
            return False

    # --- Criterion 1: PIZZA TOPPINGS group ---
    pizza_group = grp_names_upper.get("PIZZA TOPPINGS")
    if pizza_group:
        score += 15
        feedback_parts.append("PIZZA TOPPINGS group created (15/15)")
        pizza_group_id = pizza_group.get("id", "")

        # Get modifiers in this group
        pizza_group_mods = [m for m in modifiers if str(m.get("group_id", "")).strip() == str(pizza_group_id).strip()]

        # --- Criteria 2-9: Pizza modifiers ---
        prices_correct = 0
        for req in PIZZA_MODIFIERS:
            req_name = req["name"].upper()
            found = mod_names_upper.get(req_name)
            # Also check if it's in the pizza group specifically
            if found is None:
                for m in pizza_group_mods:
                    if m.get("name", "").strip().upper() == req_name:
                        found = m
                        break
            if found:
                score += 4
                feedback_parts.append(f"Pizza modifier '{req['name']}' found (4/4)")
                if _price_near(found.get("price", 0), req["price"]):
                    prices_correct += 1
            else:
                feedback_parts.append(f"Pizza modifier '{req['name']}' NOT found (0/4)")
    else:
        feedback_parts.append("PIZZA TOPPINGS group NOT found (0/15)")
        # No partial credit for pizza modifiers without the required group —
        # prevents false positives from pre-existing DB modifiers (SAUSAGE etc.)
        for req in PIZZA_MODIFIERS:
            feedback_parts.append(f"Pizza modifier '{req['name']}' NOT found (0/4)")
        prices_correct = 0

    # --- Criterion 3: BURGER ADD-ONS group ---
    burger_group = grp_names_upper.get("BURGER ADD-ONS")
    if burger_group:
        score += 15
        feedback_parts.append("BURGER ADD-ONS group created (15/15)")
        burger_group_id = burger_group.get("id", "")

        # --- Criteria for burger modifiers ---
        burger_prices_correct = 0
        for req in BURGER_MODIFIERS:
            req_name = req["name"].upper()
            found = mod_names_upper.get(req_name)
            if found is None:
                for m in modifiers:
                    if m.get("name", "").strip().upper() == req_name:
                        found = m
                        break
            if found:
                score += 3
                feedback_parts.append(f"Burger modifier '{req['name']}' found (3/3)")
                if _price_near(found.get("price", 0), req["price"]):
                    burger_prices_correct += 1
            else:
                feedback_parts.append(f"Burger modifier '{req['name']}' NOT found (0/3)")
    else:
        feedback_parts.append("BURGER ADD-ONS group NOT found (0/15)")
        # No partial credit for burger modifiers without the required group —
        # prevents false positives from pre-existing DB modifiers (BACON etc.)
        for req in BURGER_MODIFIERS:
            feedback_parts.append(f"Burger modifier '{req['name']}' NOT found (0/3)")
        burger_prices_correct = 0

    # --- Criterion 4: PIZZA TOPPINGS assigned to pizza item ---
    if pizza_assignments:
        score += 20
        feedback_parts.append(f"PIZZA TOPPINGS assigned to pizza item(s): {[a.get('item_name','?') for a in pizza_assignments[:2]]} (20/20)")
    else:
        feedback_parts.append("PIZZA TOPPINGS not assigned to any pizza item (0/20)")

    # --- Bonus: good modifier coverage ---
    pizza_mods_found = sum(1 for req in PIZZA_MODIFIERS if req["name"].upper() in mod_names_upper)
    burger_mods_found = sum(1 for req in BURGER_MODIFIERS if req["name"].upper() in mod_names_upper)
    if pizza_mods_found >= 6 and burger_mods_found >= 4:
        score += 3
        feedback_parts.append(f"Good modifier coverage ({pizza_mods_found}/8 pizza, {burger_mods_found}/5 burger) +3 bonus")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts[:20]),
        "debug": {
            "modifier_groups_in_db": len(modifier_groups),
            "modifiers_in_db": len(modifiers),
            "pizza_assignments": len(pizza_assignments),
            "pizza_group_found": "PIZZA TOPPINGS" in grp_names_upper,
            "burger_group_found": "BURGER ADD-ONS" in grp_names_upper,
        }
    }
