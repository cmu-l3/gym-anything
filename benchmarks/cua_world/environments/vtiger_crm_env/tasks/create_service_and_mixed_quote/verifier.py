#!/usr/bin/env python3
"""
Verifier for create_service_and_mixed_quote task.
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_service_and_mixed_quote(traj, env_info, task_info):
    """
    Verify the CRM mixed-quote workflow:
    - Service record created
    - Quote record created
    - Both line items (Product and Service) added properly
    - Trajectory verified with VLM to prevent direct DB injection
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_product_qty = metadata.get('expected_product_qty', 2.0)
    expected_service_qty = metadata.get('expected_service_qty', 6.0)

    score = 0
    feedback_parts = []

    # 1. Read exported results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check Service Creation (15 points)
    service_found = result.get('service_found', False)
    service = result.get('service', {})
    if service_found:
        score += 10
        if service.get('price') == 125.00 and service.get('unit') == 'Hours':
            score += 5
            feedback_parts.append("Service created perfectly")
        else:
            feedback_parts.append("Service created (pricing/unit mismatch)")
    else:
        feedback_parts.append("Service NOT found")

    # 3. Check Quote Creation & Links (15 + 10 points)
    quote_found = result.get('quote_found', False)
    quote = result.get('quote', {})
    if quote_found:
        score += 15
        
        # Verify it has accounts/contacts linked
        if quote.get('accountid') and str(quote.get('accountid')) != '0' and quote.get('contactid') and str(quote.get('contactid')) != '0':
            score += 10
            feedback_parts.append("Quote created and linked")
        else:
            feedback_parts.append("Quote created but missing Org/Contact link")
            
        # Verify addresses (10 points)
        if "100 Innovation Way" in quote.get('bill_street', ''):
            score += 10
            feedback_parts.append("Addresses populated correctly")
        else:
            feedback_parts.append("Billing address incorrect/missing")
    else:
        feedback_parts.append("Quote NOT found")

    # 4. Check Line Items (20 + 20 points)
    line_items = result.get('line_items', [])
    product_found = False
    service_line_found = False

    for item in line_items:
        name = item.get('name', '')
        qty = item.get('quantity', 0)
        
        if "Meraki MX68" in name:
            product_found = True
            if qty == expected_product_qty:
                score += 20
                feedback_parts.append("Product line item correct (Qty: 2)")
            else:
                score += 10
                feedback_parts.append(f"Product line item found (Wrong qty: {qty})")
                
        if "Network Installation" in name:
            service_line_found = True
            if qty == expected_service_qty:
                score += 20
                feedback_parts.append("Service line item correct (Qty: 6)")
            else:
                score += 10
                feedback_parts.append(f"Service line item found (Wrong qty: {qty})")

    if not product_found and quote_found:
        feedback_parts.append("Missing Product line item")
    if not service_line_found and quote_found:
        feedback_parts.append("Missing Service line item")

    # 5. Anti-gaming check via Record Increments (10 points)
    init_q = result.get('initial_quote_count', 0)
    curr_q = result.get('current_quote_count', 0)
    if curr_q > init_q:
        score += 10
        feedback_parts.append("Verified anti-gaming (records incremented)")
    else:
        # Zero out if no records were actually added (cheating)
        score = 0
        feedback_parts.append("FAIL: No new records added to database")

    # 6. VLM Trajectory Verification
    # Ensure they used the UI and didn't execute a script from terminal
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        vlm_prompt = """
        Review these screenshots from a CRM task.
        Did the user navigate the web UI to create a Service and a Quote? 
        Look for Vtiger CRM screens like "Adding New Service", "Creating New Quote", or interacting with Line Item tables (Add Product/Add Service buttons).
        Respond in JSON with {"used_ui": true/false}.
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_img], prompt=vlm_prompt)
            if vlm_res and vlm_res.get('parsed', {}).get('used_ui', False) is False:
                score = 0
                feedback_parts.append("FAIL: VLM detected no meaningful UI interaction")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")

    # Final logic
    key_criteria_met = quote_found and product_found and service_line_found
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }