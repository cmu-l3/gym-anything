#!/usr/bin/env python3
"""Verifier for XML Sitemap Setup task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_xml_sitemap_setup(traj, env_info, task_info):
    """
    Verify XML Sitemap configuration and generation.

    Criteria:
    1. Category Config (15 pts): Freq=daily, Prio=0.8
    2. Product Config (15 pts): Freq=daily, Prio=1.0
    3. CMS Page Config (15 pts): Freq=weekly, Prio=0.5
    4. Sitemap Record (20 pts): Exists in DB with correct path/filename
    5. Sitemap File (35 pts): Exists on disk, size > 0, valid XML content

    Pass threshold: 65 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    exp_cat_freq = metadata.get('expected_category_freq', 'daily')
    exp_cat_prio = metadata.get('expected_category_prio', '0.8')
    exp_prod_freq = metadata.get('expected_product_freq', 'daily')
    exp_prod_prio = metadata.get('expected_product_prio', '1.0')
    exp_page_freq = metadata.get('expected_page_freq', 'weekly')
    exp_page_prio = metadata.get('expected_page_prio', '0.5')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/sitemap_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []

    config = result.get('config', {})
    db_record = result.get('db_record', {})
    file_info = result.get('file', {})

    # 1. Category Config (15 pts)
    # Note: Magento stores 'daily', 'weekly' etc. in lowercase in core_config_data
    # Priorities are strings "0.8", "1.0"
    
    cat_freq = config.get('category_freq', '')
    cat_prio = config.get('category_prio', '')
    
    cat_ok = (cat_freq == exp_cat_freq and cat_prio == exp_cat_prio)
    if cat_ok:
        score += 15
        feedback_parts.append("Category config correct (15 pts)")
    else:
        feedback_parts.append(f"Category config mismatch: got Freq={cat_freq}, Prio={cat_prio}")

    # 2. Product Config (15 pts)
    prod_freq = config.get('product_freq', '')
    prod_prio = config.get('product_prio', '')
    
    prod_ok = (prod_freq == exp_prod_freq and prod_prio == exp_prod_prio)
    if prod_ok:
        score += 15
        feedback_parts.append("Product config correct (15 pts)")
    else:
        feedback_parts.append(f"Product config mismatch: got Freq={prod_freq}, Prio={prod_prio}")

    # 3. CMS Page Config (15 pts)
    page_freq = config.get('page_freq', '')
    page_prio = config.get('page_prio', '')
    
    page_ok = (page_freq == exp_page_freq and page_prio == exp_page_prio)
    if page_ok:
        score += 15
        feedback_parts.append("CMS Page config correct (15 pts)")
    else:
        feedback_parts.append(f"CMS Page config mismatch: got Freq={page_freq}, Prio={page_prio}")

    # 4. Sitemap DB Record (20 pts)
    if db_record.get('found', False):
        fname = db_record.get('filename', '')
        fpath = db_record.get('path', '')
        if fname == 'sitemap.xml' and fpath == '/':
            score += 20
            feedback_parts.append("Sitemap DB record correct (20 pts)")
        else:
            score += 10 # Partial credit for creating record but wrong path/name
            feedback_parts.append(f"Sitemap DB record exists but wrong path/name: {fpath}{fname} (10 pts)")
    else:
        feedback_parts.append("Sitemap DB record NOT found (0 pts)")

    # 5. Sitemap File (35 pts)
    if file_info.get('exists', False):
        if file_info.get('content_valid', False):
            score += 35
            feedback_parts.append("Sitemap file generated and valid (35 pts)")
        else:
            # Empty or invalid file
            score += 10
            feedback_parts.append("Sitemap file exists but content invalid/empty (10 pts)")
    else:
        feedback_parts.append("Sitemap file NOT generated on disk (0 pts)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }