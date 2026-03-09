#!/usr/bin/env python3
"""Verifier for Homepage Widget task in Magento.

Task: Create a 'Catalog Products List' widget named 'Homepage Featured Electronics'
for the 'Electronics' category (5 products) on CMS Home Page Main Content Area.

Criteria:
1. Widget exists with correct title (25 pts)
2. Widget type is 'Catalog Products List' (15 pts)
3. Layout update targets CMS Home Page (20 pts)
4. Layout update targets Main Content Area (10 pts)
5. Product count is set to 5 (15 pts)
6. Condition filters by Electronics category (15 pts)

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_homepage_widget(traj, env_info, task_info):
    """
    Verify widget creation.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/homepage_widget_result.json", tmp.name)
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
    subscores = {}

    # Metadata expectations
    expected_title = "Homepage Featured Electronics"
    
    # 1. Widget Exists (25 pts)
    widget_found = result.get('widget_found', False)
    title = result.get('widget_title', '')
    
    # Strict title check? Task description specified it.
    # Allow case-insensitive for robustness.
    title_match = expected_title.lower() in title.lower()
    
    if widget_found and title_match:
        score += 25
        feedback_parts.append("Widget created with correct title (25 pts)")
    elif widget_found:
        score += 10
        feedback_parts.append(f"Widget created but title mismatch: '{title}' (10 pts)")
    else:
        feedback_parts.append("Widget not found with expected title")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Correct Widget Type (15 pts)
    # Expected: Magento\CatalogWidget\Block\Product\ProductsList
    w_type = result.get('widget_type', '')
    if 'ProductsList' in w_type:
        score += 15
        feedback_parts.append("Correct widget type (15 pts)")
    else:
        feedback_parts.append(f"Incorrect widget type: {w_type}")

    # 3. Layout Update: Homepage (20 pts)
    # handle: cms_index_index
    handle = result.get('layout_handle', '')
    if handle == 'cms_index_index':
        score += 20
        feedback_parts.append("Correctly targeted CMS Home Page (20 pts)")
    else:
        feedback_parts.append(f"Incorrect page target (handle: {handle})")

    # 4. Layout Update: Container (10 pts)
    # reference: content (Main Content Area)
    ref = result.get('block_reference', '')
    if ref == 'content':
        score += 10
        feedback_parts.append("Correctly targeted Main Content Area (10 pts)")
    else:
        feedback_parts.append(f"Incorrect container (reference: {ref})")

    # 5. Product Count 5 (15 pts)
    count_5 = result.get('param_count_5', False)
    if count_5:
        score += 15
        feedback_parts.append("Product count set to 5 (15 pts)")
    else:
        feedback_parts.append("Product count not set to 5")

    # 6. Category Condition (15 pts)
    cat_match = result.get('param_cat_match', False)
    if cat_match:
        score += 15
        feedback_parts.append("Electronics category condition verified (15 pts)")
    else:
        feedback_parts.append("Category condition missing or incorrect")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "title": title_match,
            "type": 'ProductsList' in w_type,
            "homepage": handle == 'cms_index_index',
            "container": ref == 'content',
            "count": count_5,
            "condition": cat_match
        }
    }