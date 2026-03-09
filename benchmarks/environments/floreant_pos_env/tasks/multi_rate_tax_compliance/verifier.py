#!/usr/bin/env python3
"""Verifier for multi_rate_tax_compliance task.

Scoring (100 points):
- FOOD TAX created at 5.5%: 10 pts
- ALCOHOL TAX created at 9.0%: 10 pts
- RETAIL TAX created at 7.25%: 10 pts
- At least one BEER & WINE item reassigned to ALCOHOL TAX: 20 pts
- All BEER & WINE items reassigned to ALCOHOL TAX: 20 pts
- At least one RETAIL item reassigned to RETAIL TAX: 20 pts
- US tax unchanged at 6.0%: 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_multi_rate_tax_compliance(traj, env_info, task_info):
    """Verify multi-rate tax compliance configuration."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/multi_rate_tax_compliance_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    if not result.get("derby_tools_available"):
        return {"passed": False, "score": 0, "feedback": "Derby tools unavailable — cannot verify DB state"}

    score = 0
    feedback_parts = []

    taxes = result.get("taxes", [])
    items = result.get("items_with_tax", [])

    # Build tax name->rate and tax name->id maps
    tax_by_name = {}
    for t in taxes:
        name = t.get("name", "").strip().upper()
        tax_by_name[name] = t

    def _rate_near(actual_str, expected_float, tol=0.02):
        try:
            return abs(float(actual_str) - expected_float) <= tol
        except (ValueError, TypeError):
            return False

    # --- Criterion 1: FOOD TAX at 5.5% ---
    if "FOOD TAX" in tax_by_name and _rate_near(tax_by_name["FOOD TAX"].get("rate", 0), 5.5):
        score += 10
        feedback_parts.append("FOOD TAX 5.5% created (10/10)")
    else:
        feedback_parts.append("FOOD TAX 5.5% NOT found (0/10)")

    # --- Criterion 2: ALCOHOL TAX at 9.0% ---
    if "ALCOHOL TAX" in tax_by_name and _rate_near(tax_by_name["ALCOHOL TAX"].get("rate", 0), 9.0):
        score += 10
        feedback_parts.append("ALCOHOL TAX 9.0% created (10/10)")
    else:
        feedback_parts.append("ALCOHOL TAX 9.0% NOT found (0/10)")

    # --- Criterion 3: RETAIL TAX at 7.25% ---
    if "RETAIL TAX" in tax_by_name and _rate_near(tax_by_name["RETAIL TAX"].get("rate", 0), 7.25):
        score += 10
        feedback_parts.append("RETAIL TAX 7.25% created (10/10)")
    else:
        feedback_parts.append("RETAIL TAX 7.25% NOT found (0/10)")

    # Get ALCOHOL TAX id and RETAIL TAX id
    alcohol_tax_id = tax_by_name.get("ALCOHOL TAX", {}).get("id", "")
    retail_tax_id = tax_by_name.get("RETAIL TAX", {}).get("id", "")

    # --- Criteria 4 & 5: BEER & WINE items reassigned ---
    beer_wine_items = [it for it in items if it.get("category", "").strip().upper() == "BEER & WINE"]
    beer_wine_reassigned = [it for it in beer_wine_items if str(it.get("tax_id", "")).strip() == str(alcohol_tax_id).strip()]

    if beer_wine_items:
        if len(beer_wine_reassigned) >= 1:
            score += 20
            feedback_parts.append(f">=1 BEER & WINE item uses ALCOHOL TAX ({len(beer_wine_reassigned)}/{len(beer_wine_items)}) (20/20)")
        else:
            feedback_parts.append(f"No BEER & WINE items reassigned to ALCOHOL TAX (0/20)")

        if len(beer_wine_reassigned) == len(beer_wine_items) and len(beer_wine_items) > 0:
            score += 20
            feedback_parts.append(f"ALL BEER & WINE items reassigned (20/20)")
        else:
            feedback_parts.append(f"Not all BEER & WINE items reassigned ({len(beer_wine_reassigned)}/{len(beer_wine_items)}) (0/20)")
    else:
        # No beer & wine items found — still check if any items have alcohol tax assigned
        alcohol_items = [it for it in items if str(it.get("tax_id", "")).strip() == str(alcohol_tax_id).strip()]
        if alcohol_items and alcohol_tax_id:
            score += 15
            feedback_parts.append(f"{len(alcohol_items)} items use ALCOHOL TAX (partial credit, category unclear)")
        else:
            feedback_parts.append("BEER & WINE items not found or not reassigned (0/40)")

    # --- Criterion 6: RETAIL items reassigned ---
    retail_items = [it for it in items if it.get("category", "").strip().upper() == "RETAIL"]
    retail_reassigned = [it for it in retail_items if str(it.get("tax_id", "")).strip() == str(retail_tax_id).strip()]

    if retail_items:
        if len(retail_reassigned) >= 1:
            score += 20
            feedback_parts.append(f">=1 RETAIL item uses RETAIL TAX ({len(retail_reassigned)}/{len(retail_items)}) (20/20)")
        else:
            feedback_parts.append(f"No RETAIL items reassigned to RETAIL TAX (0/20)")
    else:
        feedback_parts.append("RETAIL category items not found (0/20)")

    # --- Criterion 7: US tax preserved (gated: only counts if agent created >=1 new tax) ---
    # Gate prevents do-nothing from scoring: initial DB trivially has US tax at 6%
    new_taxes_created = len(taxes) > 1  # Initial DB has exactly 1 tax (US Tax)
    if new_taxes_created and "US" in tax_by_name and _rate_near(tax_by_name["US"].get("rate", 0), 6.0):
        score += 10
        feedback_parts.append("US tax preserved at 6.0% (10/10)")
    elif not new_taxes_created:
        feedback_parts.append("US tax check skipped — no new taxes created (0/10)")
    else:
        us_rate = tax_by_name.get("US", {}).get("rate", "missing")
        feedback_parts.append(f"US tax was modified or missing (rate={us_rate}) (0/10)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "debug": {
            "total_taxes": len(taxes),
            "beer_wine_total": len(beer_wine_items),
            "beer_wine_reassigned": len(beer_wine_reassigned),
            "retail_total": len(retail_items),
            "retail_reassigned": len(retail_reassigned),
        }
    }
