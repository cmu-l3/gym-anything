#!/usr/bin/env python3
"""
Verifier for Wine Layered Navigation task.

Criteria:
1. Attributes created: wine_region, wine_varietal, wine_vintage (Dropdown type)
2. Specific options exist for each attribute
3. Attributes are Filterable (with results) in Layered Navigation
4. Attributes are Visible on Storefront, Used in Listing, and Searchable
5. Attributes assigned to 'Wine Details' group in Default attribute set
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wine_attributes(traj, env_info, task_info):
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Task Metadata for Ground Truth
    metadata = task_info.get('metadata', {})
    required_attributes = metadata.get('attributes', [])
    target_group = metadata.get('target_group', 'Wine Details')

    score = 0
    feedback = []
    
    # Check creation count (Anti-gaming)
    initial_count = result.get('initial_attr_count', 0)
    current_count = result.get('current_attr_count', 0)
    if current_count <= initial_count:
        feedback.append("⚠️ No new attributes detected (count did not increase).")

    attributes_data = result.get('attributes', {})
    
    total_items = len(required_attributes)
    # Points distribution: 
    # 3 attributes * (8 pts existence + 8 pts options + 6 pts filterable + 6 pts other props + 5 pts group) = ~99 pts
    
    for req in required_attributes:
        code = req['code']
        label = req['label']
        req_options = set(o.lower().strip() for o in req['options'])
        
        attr_feedback = f"Attribute '{code}': "
        
        # Check Existence
        if code not in attributes_data:
            feedback.append(f"❌ {attr_feedback} Not found.")
            continue
            
        data = attributes_data[code]
        
        # Check Input Type (Dropdown/Select)
        if data.get('frontend_input') == 'select':
            score += 8
        else:
            feedback.append(f"⚠️ {attr_feedback} Input type is '{data.get('frontend_input')}', expected 'Dropdown'.")

        # Check Options
        found_options = set(o.lower().strip() for o in data.get('options', []))
        # We check if all required options are present. Extra options are allowed but discouraged.
        missing_options = req_options - found_options
        if not missing_options:
            score += 8
        else:
            feedback.append(f"⚠️ {attr_feedback} Missing options: {', '.join(missing_options)}.")

        # Check Filterable (1 = Filterable with results, 2 = Filterable no results)
        # Magento stores '1' or '2' in is_filterable. '0' is No.
        is_filterable = str(data.get('is_filterable', '0'))
        if is_filterable == '1':
            score += 6
        elif is_filterable == '2':
            score += 4 # Partial credit for "Filterable (no results)"
            feedback.append(f"⚠️ {attr_feedback} Set to 'Filterable (no results)', expected 'Filterable (with results)'.")
        else:
            feedback.append(f"⚠️ {attr_feedback} Not set to Filterable in Layered Navigation.")

        # Check Other Properties (Visible, Listing, Search)
        props_score = 0
        if str(data.get('is_visible_on_front', '0')) == '1': props_score += 2
        if str(data.get('used_in_product_listing', '0')) == '1': props_score += 2
        if str(data.get('is_searchable', '0')) == '1': props_score += 2
        score += props_score
        if props_score < 6:
             feedback.append(f"⚠️ {attr_feedback} Missing visibility settings (Front/Listing/Search).")

        # Check Group Assignment
        group = data.get('group')
        if group and group.lower().strip() == target_group.lower().strip():
            score += 8
        else:
            feedback.append(f"⚠️ {attr_feedback} In group '{group}', expected '{target_group}'.")

        feedback.append(f"✅ {attr_feedback} Processed.")

    # Final tally
    final_score = min(100, score) # Cap at 100 just in case
    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": "\n".join(feedback)
    }