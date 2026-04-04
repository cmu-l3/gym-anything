#!/usr/bin/env python3
"""
Verifier for deploy_storefront_search task.

Criteria:
1. View 'catalog_search' exists (10 pts)
2. Path is '/search/catalog' (10 pts)
3. Menu link exists in Main Navigation (10 pts)
4. View has Relationship to Product Variations (25 pts) - CRITICAL
5. View has Exposed Filter for Title (15 pts)
6. View has Exposed Filter for SKU (20 pts)
7. Functional Test: URL returns 200 OK (5 pts)
8. Functional Test: Search parameters work (5 pts)

Total: 100 pts
Threshold: 70 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_storefront_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. View Exists (10 pts)
    if result.get('view_exists'):
        score += 10
        feedback.append("View 'catalog_search' created.")
        
        # Parse Config
        config = result.get('view_config', {})
        display = config.get('display', {}).get('default', {}).get('display_options', {})
        page_display = config.get('display', {}).get('page_1', {}).get('display_options', {})
        
        # Merge default options with page options if page options override them, 
        # but for existence checks, looking at 'default' is usually sufficient for filters/relationships
        # unless overridden. We check both.

        # 2. Check Path (10 pts)
        # Path is usually in page_1 display
        path = page_display.get('path')
        if not path:
             # Check if it's nested in route structure or elsewhere, usually direct key in display_options
             pass
        
        if path == 'search/catalog':
            score += 10
            feedback.append("Path configured correctly (/search/catalog).")
        else:
            feedback.append(f"Incorrect path: found '{path}', expected 'search/catalog'.")

        # 3. Check Relationship (25 pts)
        # We need a relationship to 'commerce_product_variation' or similar.
        # Key: relationships
        relationships = display.get('relationships', {})
        # Also check page override
        if page_display.get('defaults', {}).get('relationships') is False:
             relationships = page_display.get('relationships', {})
        
        has_variation_rel = False
        for rel_id, rel_data in relationships.items():
            # The table for variations is typically commerce_product_variation_field_data or similar
            # The plugin ID usually involves 'variations'
            if 'variations' in rel_data.get('field', '') or 'variations' in rel_data.get('id', '') or 'commerce_product_variation' in rel_data.get('table', ''):
                has_variation_rel = True
                break
        
        if has_variation_rel:
            score += 25
            feedback.append("Relationship to Product Variations configured.")
        else:
            feedback.append("Missing Relationship to Product Variations (required for SKU search).")

        # 4. Check Filters (Title: 15 pts, SKU: 20 pts)
        filters = display.get('filters', {})
        if page_display.get('defaults', {}).get('filters') is False:
            filters = page_display.get('filters', {})

        has_title_filter = False
        has_sku_filter = False
        
        for filter_id, filter_data in filters.items():
            exposed = filter_data.get('exposed', False)
            field = filter_data.get('field', '')
            table = filter_data.get('table', '')

            if exposed:
                # Title check (on commerce_product_field_data usually)
                if field == 'title' or field == 'name':
                    has_title_filter = True
                
                # SKU check (needs to be on variation table usually)
                if field == 'sku':
                    has_sku_filter = True

        if has_title_filter:
            score += 15
            feedback.append("Exposed Title filter found.")
        else:
            feedback.append("Exposed Title filter missing.")

        if has_sku_filter:
            score += 20
            feedback.append("Exposed SKU filter found.")
        else:
            feedback.append("Exposed SKU filter missing.")

    else:
        feedback.append("View 'catalog_search' not found.")

    # 5. Menu Link (10 pts)
    if result.get('menu_link_exists'):
        score += 10
        feedback.append("Menu link 'Search' exists.")
    else:
        feedback.append("Menu link 'Search' not found in Main Navigation.")

    # 6. Functional Checks (10 pts)
    http_status = result.get('http_status')
    if str(http_status) == '200':
        score += 5
        feedback.append("Search page is accessible (HTTP 200).")
    else:
        feedback.append(f"Search page returned HTTP {http_status}.")

    if result.get('search_functional_sku') or result.get('search_functional_title'):
        score += 5
        feedback.append("Search functionality verified via curl.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }