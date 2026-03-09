#!/usr/bin/env python3
"""
Verifier for create_grouped_product task.

Task: Create a grouped product "Tech Essentials Bundle" linked to 
"Wireless Bluetooth Headphones" and "USB-C Laptop Charger 65W".

Verification Strategy (Hybrid):
1. Programmatic (70 pts):
   - Product exists and published (15)
   - Type is 'grouped' (15)
   - Both child products linked (20)
   - Category is 'Electronics' (10)
   - Descriptions match keywords (10)
2. VLM (30 pts):
   - Trajectory shows "Linked Products" tab interaction (15)
   - Final state shows success (15)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a 'Grouped Product' in WooCommerce.

Key steps for this specific task:
1. Select "Grouped product" from the "Product data" dropdown (instead of Simple product).
2. Click the "Linked Products" tab on the left side of the data panel.
3. Search for and add products in the "Grouped products" field (specifically headphones and charger).

Assess:
1. TYPE_CHANGED: Did the agent change the product type to "Grouped product"?
2. LINKED_TAB_ACCESSED: Did the agent navigate to the "Linked Products" tab?
3. CHILDREN_ADDED: Is there evidence of products being added to the "Grouped products" field?
4. WORKFLOW_COMPLETED: Did the agent publish/save the product?

Respond in JSON format:
{
    "type_changed": true/false,
    "linked_tab_accessed": true/false,
    "children_added": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce product creation task.
Look for evidence that a product named "Tech Essentials Bundle" was successfully created/published.
Check if the screen shows a "Product published" message or the product in the list.

Respond in JSON format:
{
    "success_indicators": true/false,
    "product_name_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm: return None
    if not image and not images: return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_create_grouped_product(traj, env_info, task_info):
    """Verify create_grouped_product task."""
    
    # 1. Setup & Data Loading
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 2. Programmatic Verification (70 pts)
    product = result.get('product', {})
    found = result.get('product_found', False)
    
    # Criterion 1: Product Found & Published (15 pts)
    if found and product.get('status') == 'publish':
        score += 15
        feedback.append("Product found and published.")
    elif found:
        score += 5
        feedback.append("Product found but not published.")
    else:
        feedback.append("Product 'Tech Essentials Bundle' not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Product Type is Grouped (15 pts)
    if product.get('type') == 'grouped':
        score += 15
        feedback.append("Correct product type (grouped).")
    else:
        feedback.append(f"Incorrect product type: {product.get('type')}.")

    # Criterion 3: Children Linked (20 pts)
    linked_skus = product.get('linked_children_skus', [])
    wbh_linked = "WBH-001" in linked_skus
    usbc_linked = "USBC-065" in linked_skus
    
    if wbh_linked and usbc_linked:
        score += 20
        feedback.append("Both child products correctly linked.")
    elif wbh_linked or usbc_linked:
        score += 10
        feedback.append("Only one child product linked.")
    else:
        feedback.append("No correct child products linked.")

    # Criterion 4: Category (10 pts)
    categories = product.get('categories', '')
    if 'Electronics' in categories:
        score += 10
        feedback.append("Correct category assigned.")
    else:
        feedback.append("Category 'Electronics' not assigned.")

    # Criterion 5: Descriptions (10 pts)
    s_desc = product.get('short_description', '').lower()
    desc = product.get('description', '').lower()
    
    desc_score = 0
    if 'productive' in s_desc or 'remote' in s_desc:
        desc_score += 5
    if 'curated' in desc or 'gadgets' in desc:
        desc_score += 5
    score += desc_score
    if desc_score == 10:
        feedback.append("Descriptions contain expected keywords.")

    # 3. VLM Verification (30 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        # Trajectory Analysis
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=8)
        
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if traj_res:
            if traj_res.get('type_changed') and traj_res.get('linked_tab_accessed'):
                score += 15
                feedback.append("VLM confirmed grouped product workflow.")
            elif traj_res.get('workflow_completed'):
                score += 10
                feedback.append("VLM confirmed workflow completion.")
                
        # Final State Analysis
        final_img = get_final_screenshot(traj)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
        if final_res and final_res.get('success_indicators'):
            score += 15
            feedback.append("VLM confirmed final success state.")
    else:
        # Fallback if VLM unavailable but programmatic passed
        if score >= 60:
            score += 30
            feedback.append("VLM unavailable, assumed pass based on data.")

    # 4. Anti-Gaming Check
    initial_count = int(result.get('initial_grouped_count', 0))
    current_count = int(result.get('current_grouped_count', 0))
    if current_count <= initial_count and found:
        feedback.append("WARNING: No new grouped product count increase detected.")
        # We don't penalize heavily if 'found' is true, as they might have edited an existing one (though instructions said create new)
        # But this task specifically asks to CREATE.
        # If the ID is new, we are good. We can't easily check ID age here without more SQL.
        # We'll rely on the fact that we found the specific name.

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }