#!/usr/bin/env python3
"""
Verifier for launch_woocommerce_coffee_roastery task.

Occupation: E-Commerce Manager (SOC 11-2021.00)
Difficulty: Very Hard

Agent must activate WooCommerce, configure store settings (address, currency,
tax), create product categories with hierarchy, create a product attribute
with terms, add 6 products (3 variable with variations, 3 simple), configure
a shipping zone with two methods, and create a coupon.

This is a stub verifier. Full verification is handled by vlm_checklist_verifier.
Basic programmatic checks are provided as fallback.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/launch_woocommerce_coffee_roastery_result.json"


def verify_launch_woocommerce_coffee_roastery(traj, env_info, task_info):
    """Stub verifier with basic programmatic checks."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_FILE, temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False, "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []
    details = {}

    # ================================================================
    # 1. WooCommerce active (10 pts)
    # ================================================================
    wc_active = result.get("woocommerce_active", False)
    if wc_active:
        score += 10
        feedback.append("WooCommerce active")
    else:
        feedback.append("FAIL: WooCommerce not active")

    # ================================================================
    # 2. Store settings (6 pts)
    # ================================================================
    store = result.get("store_settings", {})
    expected_cfg = metadata.get("store_config", {})

    if store.get("currency", "").upper() == expected_cfg.get("currency", "USD"):
        score += 2
        feedback.append("Currency: USD")
    else:
        feedback.append(f"FAIL: Currency is '{store.get('currency')}'")

    # Check country contains state code (WooCommerce stores as "US:WA")
    country_val = store.get("country", "")
    if "US" in country_val:
        score += 2
        feedback.append(f"Country: {country_val}")
    else:
        feedback.append(f"FAIL: Country is '{country_val}'")

    if store.get("city", "").lower() == expected_cfg.get("city", "Seattle").lower():
        score += 1
    if store.get("postcode", "") == expected_cfg.get("postcode", "98109"):
        score += 1

    # ================================================================
    # 3. Tax enabled + rate (4 pts)
    # ================================================================
    calc_taxes = store.get("calc_taxes", "")
    tax_rates = result.get("tax_rates", [])

    if calc_taxes == "yes":
        score += 2
        feedback.append("Tax calculations enabled")
    else:
        feedback.append("FAIL: Tax calculations not enabled")

    wa_rate_found = False
    for rate in tax_rates:
        if rate.get("state", "").upper() == "WA":
            wa_rate_found = True
            # Accept 6.5, 6.5000, 6.50, etc.
            try:
                if abs(float(rate.get("rate", "0")) - 6.5) < 0.01:
                    score += 2
                    feedback.append(f"WA tax rate: {rate.get('rate')}%")
                else:
                    feedback.append(f"FAIL: WA tax rate is {rate.get('rate')}% (expected 6.5)")
            except ValueError:
                feedback.append(f"FAIL: WA tax rate invalid: {rate.get('rate')}")
    if not wa_rate_found:
        feedback.append("FAIL: No tax rate for WA state")

    # ================================================================
    # 4. Product categories (5 pts)
    # ================================================================
    categories = result.get("categories", [])
    cat_names = {c["name"] for c in categories}
    expected_parents = {"Single Origin", "Blends", "Equipment"}
    expected_children = {"African", "Americas"}

    parents_found = expected_parents & cat_names
    children_found = expected_children & cat_names

    score += len(parents_found)  # 1 pt each, max 3
    score += len(children_found)  # 1 pt each, max 2
    feedback.append(f"Categories: {len(parents_found)}/3 parents, {len(children_found)}/2 children")

    # Check hierarchy (bonus: are children parented correctly?)
    single_origin_id = None
    for c in categories:
        if c["name"] == "Single Origin":
            single_origin_id = c["term_id"]
    hierarchy_ok = True
    for c in categories:
        if c["name"] in expected_children:
            if c["parent_id"] != single_origin_id:
                hierarchy_ok = False
    details["category_hierarchy_correct"] = hierarchy_ok

    # ================================================================
    # 5. Product attribute with terms (4 pts)
    # ================================================================
    attributes = result.get("attributes", [])
    bag_size_attr = None
    for a in attributes:
        if a.get("slug", "") == "bag-size" or "bag" in a.get("label", "").lower():
            bag_size_attr = a
            break

    if bag_size_attr:
        score += 2
        feedback.append(f"Attribute '{bag_size_attr.get('label')}' found")
        expected_terms = {"250g", "500g", "1kg"}
        actual_terms = {t.strip().lower() for t in bag_size_attr.get("terms", [])}
        matched_terms = sum(1 for et in expected_terms if et.lower() in actual_terms)
        if matched_terms == 3:
            score += 2
            feedback.append("All 3 attribute terms present")
        else:
            score += 1 if matched_terms >= 1 else 0
            feedback.append(f"Attribute terms: {matched_terms}/3 found")
    else:
        feedback.append("FAIL: Bag Size attribute not found")

    # ================================================================
    # 6. Products (30 pts total)
    # ================================================================
    products = result.get("products", [])
    product_names = {p["name"] for p in products}

    # Simple products: 3 pts each = 9 pts
    simple_expected = metadata.get("products", {}).get("simple", [])
    simple_found = 0
    for sp in simple_expected:
        matching = [p for p in products if p["name"] == sp["name"]]
        if matching:
            simple_found += 1
            p = matching[0]
            pts = 1  # exists
            if p.get("regular_price") == sp.get("price"):
                pts += 1
            if p.get("sku") == sp.get("sku"):
                pts += 1
            score += pts
    feedback.append(f"Simple products: {simple_found}/{len(simple_expected)} found")

    # Variable products: 7 pts each = 21 pts (2 exists+type + 5 variations)
    variable_expected = metadata.get("products", {}).get("variable", [])
    variable_found = 0
    total_variations_correct = 0

    for vp in variable_expected:
        matching = [p for p in products if p["name"] == vp["name"]]
        if matching:
            p = matching[0]
            if p.get("type") == "variable":
                variable_found += 1
                score += 2  # exists as variable

                # Check variations
                variations = p.get("variations", [])
                expected_prices = vp.get("prices", {})
                for size, expected_price in expected_prices.items():
                    for v in variations:
                        if v.get("bag_size", "").lower() == size.lower():
                            if v.get("price") == expected_price:
                                total_variations_correct += 1
                                score += 1  # Partial credit removed; using 1 pt per variation
                            break

    # Cap variation points (9 total variations possible, score 1 each, but
    # we already added above, so just report)
    feedback.append(
        f"Variable products: {variable_found}/{len(variable_expected)} found, "
        f"{total_variations_correct}/9 variations correct"
    )

    # ================================================================
    # 7. Shipping zone (8 pts)
    # ================================================================
    zones = result.get("shipping_zones", [])
    shipping_score = 0
    if zones:
        zone = zones[0]
        shipping_score += 2  # zone exists
        # Check if US is in locations
        locs = zone.get("locations", [])
        if any(l.get("code") == "US" for l in locs):
            shipping_score += 1

        methods = zone.get("methods", [])
        method_types = {m.get("method_id") for m in methods}

        if "flat_rate" in method_types:
            shipping_score += 2
            fr = [m for m in methods if m.get("method_id") == "flat_rate"][0]
            if fr.get("cost") == "5.99":
                shipping_score += 1

        if "free_shipping" in method_types:
            shipping_score += 1
            fs = [m for m in methods if m.get("method_id") == "free_shipping"][0]
            min_amt = fs.get("min_amount", "")
            try:
                if abs(float(min_amt) - 75.0) < 0.01:
                    shipping_score += 1
            except (ValueError, TypeError):
                pass

    score += shipping_score
    feedback.append(f"Shipping: {shipping_score}/8 pts")

    # ================================================================
    # 8. Coupon (8 pts)
    # ================================================================
    coupons = result.get("coupons", [])
    coupon_score = 0
    if coupons:
        # Find GRANDOPENING coupon (WooCommerce lowercases codes)
        gc = None
        for c in coupons:
            if c.get("code", "").lower() == "grandopening":
                gc = c
                break

        if gc:
            coupon_score += 2  # coupon exists
            if gc.get("discount_type") == "percent":
                coupon_score += 2
            try:
                if abs(float(gc.get("amount", "0")) - 20.0) < 0.01:
                    coupon_score += 2
            except (ValueError, TypeError):
                pass
            if gc.get("usage_limit") == "500":
                coupon_score += 1
            # date_expires is a Unix timestamp for 2026-12-31
            if gc.get("date_expires"):
                coupon_score += 1

    score += coupon_score
    feedback.append(f"Coupon: {coupon_score}/8 pts")

    # ================================================================
    # Summary
    # ================================================================
    details.update({
        "wc_active": wc_active,
        "simple_products_found": simple_found,
        "variable_products_found": variable_found,
        "total_variations_correct": total_variations_correct,
        "categories_count": len(categories),
        "attributes_count": len(attributes),
        "shipping_zones_count": len(zones),
        "coupons_count": len(coupons),
        "shipping_score": shipping_score,
        "coupon_score": coupon_score,
    })

    passed = (
        score >= 50
        and wc_active
        and variable_found >= 2
        and simple_found >= 2
    )

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "details": details,
    }
