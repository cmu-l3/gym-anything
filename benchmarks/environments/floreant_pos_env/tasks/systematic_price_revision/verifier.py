#!/usr/bin/env python3
"""Verifier for systematic_price_revision task.

Scoring (100 points):
- HAMMER COFFEE price updated to $3.75: 15 pts
- SMK HOUS B FAST price updated to $10.50: 15 pts
- OLD TIMER B FAST price updated to $9.75: 15 pts
- PREMIUM SELECTIONS category created: 15 pts
- WAGYU BEEF BURGER at $24.95: 10 pts
- TRUFFLE FRIES at $12.95: 10 pts
- ARTISAN CHEESE PLATE at $18.50: 10 pts
- All 3 new items AND all 3 price updates correct (bonus): 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_systematic_price_revision(traj, env_info, task_info):
    """Verify systematic price revision and premium tier launch."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/systematic_price_revision_result.json", tmp.name)
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

    def _price_near(actual_str, expected, tol=0.02):
        try:
            return abs(float(actual_str) - expected) <= tol
        except (ValueError, TypeError):
            return False

    items = result.get("items", [])
    categories = result.get("categories", [])
    cat_names_upper = {c["name"].strip().upper() for c in categories}
    item_names_upper = {it["name"].strip().upper(): it for it in items}

    price_updates_ok = 0

    # --- Criterion 1: HAMMER COFFEE at $3.75 ---
    hammer = item_names_upper.get("HAMMER COFFEE")
    if hammer and _price_near(hammer.get("price", 0), 3.75):
        score += 15
        price_updates_ok += 1
        feedback_parts.append("HAMMER COFFEE updated to $3.75 (15/15)")
    elif hammer:
        feedback_parts.append(f"HAMMER COFFEE found but price wrong: {hammer.get('price')} (0/15)")
    else:
        feedback_parts.append("HAMMER COFFEE NOT found in DB (0/15)")

    # --- Criterion 2: SMK HOUS B FAST at $10.50 ---
    smk = item_names_upper.get("SMK HOUS B FAST")
    if smk and _price_near(smk.get("price", 0), 10.50):
        score += 15
        price_updates_ok += 1
        feedback_parts.append("SMK HOUS B FAST updated to $10.50 (15/15)")
    elif smk:
        feedback_parts.append(f"SMK HOUS B FAST found but price wrong: {smk.get('price')} (0/15)")
    else:
        feedback_parts.append("SMK HOUS B FAST NOT found in DB (0/15)")

    # --- Criterion 3: OLD TIMER B FAST at $9.75 ---
    old_timer = item_names_upper.get("OLD TIMER B FAST")
    if old_timer and _price_near(old_timer.get("price", 0), 9.75):
        score += 15
        price_updates_ok += 1
        feedback_parts.append("OLD TIMER B FAST updated to $9.75 (15/15)")
    elif old_timer:
        feedback_parts.append(f"OLD TIMER B FAST found but price wrong: {old_timer.get('price')} (0/15)")
    else:
        feedback_parts.append("OLD TIMER B FAST NOT found in DB (0/15)")

    # --- Criterion 4: PREMIUM SELECTIONS category ---
    if "PREMIUM SELECTIONS" in cat_names_upper:
        score += 15
        feedback_parts.append("PREMIUM SELECTIONS category created (15/15)")
    else:
        feedback_parts.append("PREMIUM SELECTIONS category NOT found (0/15)")

    new_items_ok = 0

    # --- Criterion 5: WAGYU BEEF BURGER at $24.95 ---
    wagyu = item_names_upper.get("WAGYU BEEF BURGER")
    if wagyu and _price_near(wagyu.get("price", 0), 24.95):
        score += 10
        new_items_ok += 1
        feedback_parts.append("WAGYU BEEF BURGER at $24.95 (10/10)")
    elif wagyu:
        feedback_parts.append(f"WAGYU BEEF BURGER found but price wrong: {wagyu.get('price')} (0/10)")
    else:
        feedback_parts.append("WAGYU BEEF BURGER NOT found (0/10)")

    # --- Criterion 6: TRUFFLE FRIES at $12.95 ---
    truffle = item_names_upper.get("TRUFFLE FRIES")
    if truffle and _price_near(truffle.get("price", 0), 12.95):
        score += 10
        new_items_ok += 1
        feedback_parts.append("TRUFFLE FRIES at $12.95 (10/10)")
    elif truffle:
        feedback_parts.append(f"TRUFFLE FRIES found but price wrong: {truffle.get('price')} (0/10)")
    else:
        feedback_parts.append("TRUFFLE FRIES NOT found (0/10)")

    # --- Criterion 7: ARTISAN CHEESE PLATE at $18.50 ---
    cheese = item_names_upper.get("ARTISAN CHEESE PLATE")
    if cheese and _price_near(cheese.get("price", 0), 18.50):
        score += 10
        new_items_ok += 1
        feedback_parts.append("ARTISAN CHEESE PLATE at $18.50 (10/10)")
    elif cheese:
        feedback_parts.append(f"ARTISAN CHEESE PLATE found but price wrong: {cheese.get('price')} (0/10)")
    else:
        feedback_parts.append("ARTISAN CHEESE PLATE NOT found (0/10)")

    # --- Criterion 8: Bonus for completing everything ---
    if price_updates_ok == 3 and new_items_ok == 3:
        score += 10
        feedback_parts.append("All 6 changes complete — full bonus (10/10)")
    else:
        feedback_parts.append(f"Partial completion: {price_updates_ok}/3 price updates, {new_items_ok}/3 new items (0/10)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "debug": {
            "price_updates_correct": price_updates_ok,
            "new_items_correct": new_items_ok,
            "total_items_in_db": len(items),
            "total_categories": len(categories),
        }
    }
