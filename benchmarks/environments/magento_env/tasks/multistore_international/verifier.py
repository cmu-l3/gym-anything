#!/usr/bin/env python3
"""Verifier for Multi-Store International task in Magento.

Task: Create 'NestWell Europe' store group, add 'nestwell_fr' and 'nestwell_de' views,
configure locales (fr_FR, de_DE), and add EUR currency.

Scored on 7 criteria (100 pts total). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_multistore_international(traj, env_info, task_info):
    """
    Verify multi-store setup and configuration.

    Criteria:
    1. Store Group 'NestWell Europe' exists (15 pts)
    2. French Store View 'nestwell_fr' exists & active (15 pts)
    3. German Store View 'nestwell_de' exists & active (15 pts)
    4. Both views are assigned to the correct Store Group (10 pts)
    5. French view locale is 'fr_FR' (15 pts)
    6. German view locale is 'de_DE' (15 pts)
    7. EUR is in allowed currencies (15 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/multistore_result.json", tmp.name)
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

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Check Store Group (15 pts)
    group_found = result.get('group_found', False)
    group_id = result.get('group_id')
    group_name = result.get('group_name', '')
    
    if group_found:
        score += 15
        feedback_parts.append(f"Store Group '{group_name}' created (15 pts)")
    else:
        feedback_parts.append("Store Group 'NestWell Europe' NOT found")

    # 2. Check French View (15 pts)
    fr_found = result.get('fr_view_found', False)
    fr_active = str(result.get('fr_active', '0')).strip() == '1'
    fr_group_id = result.get('fr_group_id')
    
    if fr_found and fr_active:
        score += 15
        feedback_parts.append("French Store View created & active (15 pts)")
    elif fr_found:
        score += 5
        feedback_parts.append("French Store View found but not active (5 pts)")
    else:
        feedback_parts.append("French Store View 'nestwell_fr' NOT found")

    # 3. Check German View (15 pts)
    de_found = result.get('de_view_found', False)
    de_active = str(result.get('de_active', '0')).strip() == '1'
    de_group_id = result.get('de_group_id')
    
    if de_found and de_active:
        score += 15
        feedback_parts.append("German Store View created & active (15 pts)")
    elif de_found:
        score += 5
        feedback_parts.append("German Store View found but not active (5 pts)")
    else:
        feedback_parts.append("German Store View 'nestwell_de' NOT found")

    # 4. Check Group Linkage (10 pts)
    linkage_ok = False
    if group_found and fr_found and de_found:
        if str(fr_group_id) == str(group_id) and str(de_group_id) == str(group_id):
            score += 10
            linkage_ok = True
            feedback_parts.append("Store Views correctly assigned to Group (10 pts)")
        else:
            feedback_parts.append("Store Views NOT assigned to 'NestWell Europe' group")
    
    # 5. Check French Locale (15 pts)
    fr_locale = result.get('fr_locale', '')
    if fr_locale == 'fr_FR':
        score += 15
        feedback_parts.append("French locale set to fr_FR (15 pts)")
    elif fr_found:
        feedback_parts.append(f"French locale incorrect: got '{fr_locale}'")

    # 6. Check German Locale (15 pts)
    de_locale = result.get('de_locale', '')
    if de_locale == 'de_DE':
        score += 15
        feedback_parts.append("German locale set to de_DE (15 pts)")
    elif de_found:
        feedback_parts.append(f"German locale incorrect: got '{de_locale}'")

    # 7. Check Currency (15 pts)
    eur_allowed = result.get('eur_currency_allowed', False)
    if eur_allowed:
        score += 15
        feedback_parts.append("EUR added to allowed currencies (15 pts)")
    else:
        feedback_parts.append("EUR currency NOT found in allowed list")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }