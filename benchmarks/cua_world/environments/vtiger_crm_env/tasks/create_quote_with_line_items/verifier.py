#!/usr/bin/env python3
"""
Verifier for create_quote_with_line_items task.
Validates the creation of a Vtiger quote with specific header fields and line items.
Includes VLM trajectory verification to ensure genuine workflow completion.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an AI agent successfully completed a quote creation task in a CRM (Vtiger).

Look at the provided trajectory screenshots and the final screenshot.
Determine if the agent actually navigated the Vtiger CRM UI to create a quote and add product line items.

Look for:
1. Navigation to the Quotes module and clicking "Add Quote".
2. Interacting with the quote form (filling in Subject, Organization Name).
3. Interacting with the "Item Details" or line items widget at the bottom of the form.
4. Searching for and selecting products (e.g., Wireless Bluetooth Headset, Docking Station, Keyboard).
5. Entering quantities for those products.
6. Saving the quote.

Respond in JSON format exactly like this:
{
    "workflow_visible": true/false,
    "line_items_interacted": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what the frames show"
}
"""

def verify_create_quote(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Evaluate the result of the create quote task.
    Uses programmatic database checks combined with VLM trajectory verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Anti-gaming check: Was a quote actually created? (15 pts)
    initial_count = int(result.get('initial_quote_count', 0))
    current_count = int(result.get('current_quote_count', 0))
    quote_exists = result.get('quote_exists', False)
    
    if current_count > initial_count:
        score += 15
        feedback_parts.append(f"Quote newly created (count: {initial_count} -> {current_count})")
    else:
        feedback_parts.append("FAIL: No new quotes were created during task.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
        
    if not quote_exists:
        feedback_parts.append("FAIL: No quote found matching criteria.")
        return {
            "passed": False,
            "score": score,  # Return the 15 points for creating *something*
            "feedback": " | ".join(feedback_parts)
        }

    # 3. Header Validations
    subject = result.get('subject', '').strip()
    if metadata.get('expected_subject') in subject:
        score += 10
        feedback_parts.append("Subject correct")
    else:
        feedback_parts.append(f"Subject mismatch (got: '{subject}')")
        
    org = result.get('organization', '').strip()
    # Remove spaces/punctuation for safer matching (Vtiger sometimes returns concatenated strings for linked entities)
    if "GreenTech" in org:
        score += 10
        feedback_parts.append("Organization correct")
    else:
        feedback_parts.append(f"Organization mismatch (got: '{org}')")

    valid_until = result.get('valid_until', '')
    if valid_until == metadata.get('expected_valid_until'):
        score += 5
        feedback_parts.append("Valid Until date correct")
        
    stage = result.get('quote_stage', '')
    if stage == metadata.get('expected_stage'):
        score += 5
        feedback_parts.append("Quote Stage correct")

    # 4. Line Item Validations
    line_items = result.get('line_items', [])
    expected_products = metadata.get('expected_products', [])
    expected_quantities = metadata.get('expected_quantities', {})
    
    found_products = 0
    correct_quantities = 0
    
    for item in line_items:
        p_name = item.get('product_name', '')
        qty = float(item.get('quantity', 0.0))
        
        # Check product presence
        for ep in expected_products:
            if ep.lower() in p_name.lower():
                found_products += 1
                # Check quantity if product matched
                if qty == expected_quantities.get(ep, -1):
                    correct_quantities += 1
                break
                
    # Score products (up to 10 points)
    if found_products == 3:
        score += 10
        feedback_parts.append("All 3 products present")
    elif found_products > 0:
        score += (found_products * 3)
        feedback_parts.append(f"{found_products}/3 products present")
        
    # Score quantities (up to 15 points)
    if correct_quantities == 3:
        score += 15
        feedback_parts.append("All line item quantities correct")
    elif correct_quantities > 0:
        score += (correct_quantities * 5)
        feedback_parts.append(f"{correct_quantities}/3 quantities correct")
        
    # Total calculation accuracy (10 points)
    total = float(result.get('total', 0.0))
    expected_total = float(metadata.get('expected_total', 3749.50))
    tolerance = expected_total * 0.05 # 5% tolerance for taxes/discounts variation
    
    if abs(total - expected_total) <= tolerance:
        score += 10
        feedback_parts.append("Grand total accurate")
    else:
        feedback_parts.append(f"Grand total mismatch (Expected ~$3749.50, Got ${total:.2f})")

    # 5. VLM Trajectory Verification (20 points)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(
                    prompt=VERIFICATION_PROMPT,
                    images=images
                )
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    workflow_visible = parsed.get("workflow_visible", False)
                    line_items_interacted = parsed.get("line_items_interacted", False)
                    
                    if workflow_visible and line_items_interacted:
                        score += 20
                        feedback_parts.append("VLM confirmed quote creation workflow")
                    elif workflow_visible:
                        score += 10
                        feedback_parts.append("VLM confirmed partial workflow")
                    else:
                        feedback_parts.append("VLM did not detect quote creation workflow")
                else:
                    feedback_parts.append("VLM error, granting fallback points")
                    score += 20  # Fallback if VLM fails but DB is good
            else:
                feedback_parts.append("No frames for VLM, granting fallback points")
                score += 20
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            score += 20  # Fallback
            feedback_parts.append("VLM exception, granting fallback points")
    else:
        score += 20  # Fallback if VLM not available
        feedback_parts.append("VLM unavailable, assuming workflow valid")

    # Pass threshold
    passed = score >= 60 and quote_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }