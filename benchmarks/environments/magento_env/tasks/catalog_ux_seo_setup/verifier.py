#!/usr/bin/env python3
"""Verifier for Catalog UX/SEO Setup task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_catalog_ux_seo_setup(traj, env_info, task_info):
    """
    Verify Catalog Configuration settings.

    Criteria:
    1. List Mode = Grid Only ('grid') (15 pts)
    2. Grid per page allowed values = '12,24,48' (20 pts)
    3. Default products per page = '24' (15 pts)
    4. Product Sort By = 'Price' ('price') (20 pts)
    5. Canonical Categories = Yes ('1') (15 pts)
    6. Canonical Products = Yes ('1') (15 pts)

    Pass threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_list_mode = metadata.get('expected_list_mode', 'grid')
    expected_grid_values = metadata.get('expected_grid_per_page_values', '12,24,48')
    expected_grid_default = metadata.get('expected_grid_per_page', '24')
    expected_sort_by = metadata.get('expected_sort_by', 'price')
    expected_canonical_cat = metadata.get('expected_canonical_category', '1')
    expected_canonical_prod = metadata.get('expected_canonical_product', '1')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/catalog_config_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. List Mode (15 pts)
    val = result.get('list_mode', '').strip()
    if val == expected_list_mode:
        score += 15
        feedback_parts.append("List Mode correct (Grid Only)")
    else:
        feedback_parts.append(f"List Mode incorrect: expected '{expected_list_mode}', got '{val}' (Check Storefront > List Mode)")

    # 2. Grid Values (20 pts)
    val = result.get('grid_per_page_values', '').strip().replace(' ', '')
    exp = expected_grid_values.replace(' ', '')
    if val == exp:
        score += 20
        feedback_parts.append("Grid Allowed Values correct")
    else:
        feedback_parts.append(f"Grid Allowed Values incorrect: expected '{expected_grid_values}', got '{val}'")

    # 3. Grid Default (15 pts)
    val = result.get('grid_per_page', '').strip()
    if val == expected_grid_default:
        score += 15
        feedback_parts.append("Grid Default Page correct")
    else:
        feedback_parts.append(f"Grid Default Page incorrect: expected '{expected_grid_default}', got '{val}'")

    # 4. Sort By (20 pts)
    val = result.get('default_sort_by', '').strip()
    if val == expected_sort_by:
        score += 20
        feedback_parts.append("Sort By Price correct")
    else:
        feedback_parts.append(f"Sort By incorrect: expected '{expected_sort_by}', got '{val}'")

    # 5. Canonical Category (15 pts)
    val = str(result.get('category_canonical_tag', '')).strip()
    if val == expected_canonical_cat:
        score += 15
        feedback_parts.append("Canonical Category enabled")
    else:
        feedback_parts.append(f"Canonical Category incorrect: expected '{expected_canonical_cat}', got '{val}'")

    # 6. Canonical Product (15 pts)
    val = str(result.get('product_canonical_tag', '')).strip()
    if val == expected_canonical_prod:
        score += 15
        feedback_parts.append("Canonical Product enabled")
    else:
        feedback_parts.append(f"Canonical Product incorrect: expected '{expected_canonical_prod}', got '{val}'")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }