#!/usr/bin/env python3
"""Verifier for patio_section_with_cocktail_menu task.

Scoring (100 points):
- PATIO floor section created: 15 pts
- Each of 6 patio tables (P1-P6) found: 4 pts each = 24 pts
- LIQUOR TAX at 9.5%: 15 pts
- PATIO SPECIALS category: 10 pts
- Each of 5 items with correct name (4 pts each): 20 pts
- Each of 5 items with correct price (3.2 pts each): 16 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

REQUIRED_ITEMS = [
    {"name": "SANGRIA PITCHER", "price": 18.00},
    {"name": "PALOMA COCKTAIL", "price": 11.00},
    {"name": "DRAFT BEER PATIO", "price": 6.50},
    {"name": "LOADED NACHOS", "price": 13.95},
    {"name": "GRILLED CORN", "price": 4.75},
]


def verify_patio_section_with_cocktail_menu(traj, env_info, task_info):
    """Verify patio section and cocktail menu configuration."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/patio_section_with_cocktail_menu_result.json", tmp.name)
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

    taxes = result.get("taxes", [])
    categories = result.get("categories", [])
    items = result.get("items", [])
    floors = result.get("floors", [])
    shop_tables = result.get("shop_tables", [])

    tax_names_upper = {t["name"].strip().upper(): t for t in taxes}
    cat_names_upper = {c["name"].strip().upper() for c in categories}
    item_names_upper = {it["name"].strip().upper(): it for it in items}
    floor_names_upper = {f["name"].strip().upper(): f for f in floors}
    table_names_upper = {tbl["name"].strip().upper(): tbl for tbl in shop_tables}

    def _rate_near(actual_str, expected, tol=0.02):
        try:
            return abs(float(actual_str) - expected) <= tol
        except (ValueError, TypeError):
            return False

    def _price_near(actual_str, expected, tol=0.02):
        try:
            return abs(float(actual_str) - expected) <= tol
        except (ValueError, TypeError):
            return False

    # --- Criterion 1: PATIO floor section ---
    patio_floor = floor_names_upper.get("PATIO")
    if patio_floor:
        score += 15
        feedback_parts.append("PATIO floor section created (15/15)")
        patio_floor_id = patio_floor.get("id", "")

        # --- Criterion 2: 6 PATIO tables ---
        patio_table_count = 0
        for tname in ["P1", "P2", "P3", "P4", "P5", "P6"]:
            tbl = table_names_upper.get(tname)
            if tbl and str(tbl.get("floor_id", "")) == str(patio_floor_id):
                patio_table_count += 1
                score += 4
                feedback_parts.append(f"Table {tname} in PATIO (4/4)")
            elif tbl:
                # Table exists but floor assignment unclear
                patio_table_count += 1
                score += 2
                feedback_parts.append(f"Table {tname} exists (floor unverified) (2/4)")
            else:
                feedback_parts.append(f"Table {tname} NOT found (0/4)")
    else:
        feedback_parts.append("PATIO floor section NOT created (0/15)")
        # No partial credit for tables without confirmed PATIO floor — prevents false positives
        for tname in ["P1", "P2", "P3", "P4", "P5", "P6"]:
            feedback_parts.append(f"Table {tname}: PATIO floor required first (0/4)")

    # --- Criterion 3: LIQUOR TAX ---
    liquor_tax = tax_names_upper.get("LIQUOR TAX")
    if liquor_tax and _rate_near(liquor_tax.get("rate", 0), 9.5):
        score += 15
        feedback_parts.append("LIQUOR TAX at 9.5% created (15/15)")
    else:
        feedback_parts.append(f"LIQUOR TAX 9.5% NOT found (0/15)")

    # --- Criterion 4: PATIO SPECIALS category ---
    if "PATIO SPECIALS" in cat_names_upper:
        score += 10
        feedback_parts.append("PATIO SPECIALS category created (10/10)")
    else:
        feedback_parts.append("PATIO SPECIALS category NOT found (0/10)")

    # --- Criteria 5-9: Menu items ---
    for req in REQUIRED_ITEMS:
        req_name = req["name"].upper()
        found = item_names_upper.get(req_name)
        if found is None:
            # Only match if required name is contained in DB name (not the reverse —
            # prevents "DRAFT BEER" from matching "DRAFT BEER PATIO")
            for iname, idata in item_names_upper.items():
                if req_name in iname:
                    found = idata
                    break
        if found:
            score += 4
            feedback_parts.append(f"Item '{req['name']}' found (4/4)")
            if _price_near(found.get("price", 0), req["price"]):
                score += 3
                feedback_parts.append(f"  Price ${req['price']} correct (3/3)")
            else:
                feedback_parts.append(f"  Price wrong: got {found.get('price')}, expected ${req['price']} (0/3)")
        else:
            feedback_parts.append(f"Item '{req['name']}' NOT found (0/7)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts[:20]),
        "debug": {
            "floors_in_db": len(floors),
            "tables_in_db": len(shop_tables),
            "taxes_in_db": len(taxes),
            "categories_in_db": len(categories),
            "items_in_db": len(items),
        }
    }
