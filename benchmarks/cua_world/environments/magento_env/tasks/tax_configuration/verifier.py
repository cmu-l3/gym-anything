#!/usr/bin/env python3
"""Verifier for Tax Configuration task in Magento.

Task: Create 'Industrial Machinery' product tax class, California (7.25%) and
New York (4.00%) tax rates, then a tax rule linking all three.

Tax rates are real published state base rates:
  - CA: 7.25% (California Board of Equalization, effective 2017)
  - NY: 4.00% (New York State Department of Taxation)

Scored on 5 criteria (100 pts). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tax_configuration(traj, env_info, task_info):
    """
    Verify multi-state tax configuration.

    Criteria:
    1. Product tax class 'Industrial Machinery' created (20 pts)
    2. California tax rate at 7.25% created (20 pts)
    3. New York tax rate at 4.00% created (20 pts)
    4. Tax rule 'Industrial Equipment Tax Rule' exists (15 pts)
    5. Tax rule links both CA and NY rates to Industrial Machinery class (25 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/tax_configuration_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: Industrial Machinery product tax class exists (20 pts) ───
    tax_class_found = result.get('tax_class_found', False)
    tax_class_name = result.get('tax_class_name', '').strip().lower()
    tax_class_type = result.get('tax_class_type', '').strip().upper()

    class_ok = tax_class_found and 'industrial' in tax_class_name and tax_class_type == 'PRODUCT'
    if class_ok:
        score += 20
        feedback_parts.append(f"Product tax class '{result.get('tax_class_name')}' created (20 pts)")
    elif tax_class_found:
        score += 10
        feedback_parts.append(
            f"Tax class found ('{result.get('tax_class_name')}') but type should be PRODUCT, got '{tax_class_type}' (10 pts partial)"
        )
    else:
        feedback_parts.append(
            "Product tax class 'Industrial Machinery' NOT found. "
            "Go to Stores > Taxes > Product Tax Classes and add it."
        )
    subscores['tax_class_created'] = class_ok

    # ── Criterion 2: California tax rate at 7.25% (20 pts) ───────────────────
    ca_rate_found = result.get('ca_rate_found', False)
    ca_rate_str = result.get('ca_rate_percent', '0')

    ca_rate_ok = False
    ca_rate_val = 0.0
    try:
        ca_rate_val = float(ca_rate_str) if ca_rate_str else 0.0
        ca_rate_ok = ca_rate_found and abs(ca_rate_val - 7.25) < 0.02
    except (ValueError, TypeError):
        pass

    if ca_rate_ok:
        score += 20
        feedback_parts.append(f"California tax rate {ca_rate_val}% created (20 pts)")
    elif ca_rate_found:
        score += 8
        feedback_parts.append(
            f"California tax rate exists but rate is {ca_rate_val}%, expected 7.25% (8 pts partial)"
        )
    else:
        feedback_parts.append(
            "California State Tax rate NOT found. "
            "Go to Stores > Taxes > Tax Zones and Rates and add it (US, CA, 7.25%)."
        )
    subscores['ca_rate_correct'] = ca_rate_ok

    # ── Criterion 3: New York tax rate at 4.00% (20 pts) ─────────────────────
    ny_rate_found = result.get('ny_rate_found', False)
    ny_rate_str = result.get('ny_rate_percent', '0')

    ny_rate_ok = False
    ny_rate_val = 0.0
    try:
        ny_rate_val = float(ny_rate_str) if ny_rate_str else 0.0
        ny_rate_ok = ny_rate_found and abs(ny_rate_val - 4.00) < 0.02
    except (ValueError, TypeError):
        pass

    if ny_rate_ok:
        score += 20
        feedback_parts.append(f"New York tax rate {ny_rate_val}% created (20 pts)")
    elif ny_rate_found:
        score += 8
        feedback_parts.append(
            f"New York tax rate exists but rate is {ny_rate_val}%, expected 4.00% (8 pts partial)"
        )
    else:
        feedback_parts.append(
            "New York State Tax rate NOT found. "
            "Go to Stores > Taxes > Tax Zones and Rates and add it (US, NY, 4.00%)."
        )
    subscores['ny_rate_correct'] = ny_rate_ok

    # ── Criterion 4: Tax rule exists (15 pts) ────────────────────────────────
    rule_found = result.get('rule_found', False)
    rule_code = result.get('rule_code', '').strip().lower()

    rule_ok = rule_found and 'industrial' in rule_code
    if rule_ok:
        score += 15
        feedback_parts.append(f"Tax rule '{result.get('rule_code')}' created (15 pts)")
    elif rule_found:
        score += 8
        feedback_parts.append(
            f"Tax rule found ('{result.get('rule_code')}') but name should contain 'Industrial' (8 pts partial)"
        )
    else:
        feedback_parts.append(
            "Tax rule NOT found. Go to Stores > Taxes > Tax Rules and create 'Industrial Equipment Tax Rule'."
        )
    subscores['rule_created'] = rule_ok

    # ── Criterion 5: Rule links both rates AND the product class (25 pts) ─────
    links_ca = result.get('rule_links_ca_rate', False)
    links_ny = result.get('rule_links_ny_rate', False)
    links_class = result.get('rule_links_product_class', False)
    linked_rate_count = int(result.get('rule_linked_rate_count', 0))

    # Partial credit: 10 pts each for CA + NY rate, 5 pts for product class
    rule_link_score = 0
    if links_ca:
        rule_link_score += 10
        feedback_parts.append("Rule linked to CA rate")
    else:
        feedback_parts.append("Rule NOT linked to California State Tax rate")

    if links_ny:
        rule_link_score += 10
        feedback_parts.append("Rule linked to NY rate")
    else:
        feedback_parts.append("Rule NOT linked to New York State Tax rate")

    if links_class:
        rule_link_score += 5
        feedback_parts.append("Rule linked to Industrial Machinery product class")
    elif rule_found and linked_rate_count >= 2:
        # If the class wasn't found but the rule has 2+ rates, give partial credit
        rule_link_score += 2
        feedback_parts.append(
            "Rule has 2+ rates but Industrial Machinery class not confirmed "
            "(product class may not exist yet)"
        )
    else:
        feedback_parts.append(
            "Rule NOT linked to Industrial Machinery product class"
        )

    score += rule_link_score
    if rule_link_score >= 25:
        feedback_parts.append("Rule fully configured with both rates and product class (25 pts)")
    subscores['rule_links_complete'] = (links_ca and links_ny and links_class)

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
