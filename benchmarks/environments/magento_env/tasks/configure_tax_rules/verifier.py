#!/usr/bin/env python3
"""Verifier for Configure Tax Rules task in Magento.

Task: Create 'Physical Goods' product tax class, 3 specific state tax rates,
and a 'US Multi-State Sales Tax' rule linking them together.

Scored on 8 criteria (100 pts total). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_tax_rules(traj, env_info, task_info):
    """
    Verify tax configuration.

    Criteria:
    1. Product tax class 'Physical Goods' exists (15 pts)
    2. CA rate exists with 7.25% (12 pts)
    3. NY rate exists with 8.00% (12 pts)
    4. TX rate exists with 6.25% (12 pts)
    5. Tax rule 'US Multi-State Sales Tax' exists (14 pts)
    6. Rule is linked to all 3 rates (15 pts)
    7. Rule is linked to 'Physical Goods' class (10 pts)
    8. Rule is linked to 'Retail Customer' class (10 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/tax_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Product Class (15 pts)
    if result.get('class_found', False):
        score += 15
        feedback_parts.append("Product Tax Class 'Physical Goods' found (15 pts)")
    else:
        feedback_parts.append("Product Tax Class 'Physical Goods' NOT found")

    # 2. Rates (36 pts total, 12 each)
    # Check CA
    ca_rate = float(result.get('rate_ca_val', 0))
    if result.get('rate_ca_found', False) and abs(ca_rate - 7.25) < 0.01:
        score += 12
        feedback_parts.append("CA rate correct (12 pts)")
    else:
        feedback_parts.append(f"CA rate incorrect/missing (found {ca_rate}%)")

    # Check NY
    ny_rate = float(result.get('rate_ny_val', 0))
    if result.get('rate_ny_found', False) and abs(ny_rate - 8.00) < 0.01:
        score += 12
        feedback_parts.append("NY rate correct (12 pts)")
    else:
        feedback_parts.append(f"NY rate incorrect/missing (found {ny_rate}%)")

    # Check TX
    tx_rate = float(result.get('rate_tx_val', 0))
    if result.get('rate_tx_found', False) and abs(tx_rate - 6.25) < 0.01:
        score += 12
        feedback_parts.append("TX rate correct (12 pts)")
    else:
        feedback_parts.append(f"TX rate incorrect/missing (found {tx_rate}%)")

    # 3. Rule Existence (14 pts)
    if result.get('rule_found', False):
        score += 14
        feedback_parts.append("Tax Rule found (14 pts)")
    else:
        feedback_parts.append("Tax Rule 'US Multi-State Sales Tax' NOT found")

    # 4. Linkages (35 pts total)
    # Rates linkage (15 pts - 5 each)
    rates_linked = 0
    if result.get('link_ca', False): rates_linked += 1
    if result.get('link_ny', False): rates_linked += 1
    if result.get('link_tx', False): rates_linked += 1
    
    link_score = rates_linked * 5
    score += link_score
    if rates_linked == 3:
        feedback_parts.append("Rule linked to all rates (15 pts)")
    else:
        feedback_parts.append(f"Rule linked to {rates_linked}/3 rates")

    # Product Class Linkage (10 pts)
    if result.get('link_prod_class', False):
        score += 10
        feedback_parts.append("Rule linked to Product Class (10 pts)")
    else:
        feedback_parts.append("Rule NOT linked to 'Physical Goods'")

    # Customer Class Linkage (10 pts)
    if result.get('link_cust_class', False):
        score += 10
        feedback_parts.append("Rule linked to Customer Class (10 pts)")
    else:
        feedback_parts.append("Rule NOT linked to 'Retail Customer'")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }