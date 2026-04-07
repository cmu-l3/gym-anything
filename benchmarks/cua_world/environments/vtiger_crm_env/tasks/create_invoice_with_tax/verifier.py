#!/usr/bin/env python3
"""
Verifier for create_invoice_with_tax task.
Checks database extracts for proper invoicing, line item allocation, and tax calculation.
Also includes a VLM check to ensure the agent actively used the CRM interface.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an AI agent successfully used a CRM system to create an invoice.
Look at the sequence of screenshots showing the agent's workflow.
1. Did the agent interact with an "Invoice" creation form?
2. Did the agent select or enter products/line items?
3. Did the agent apply a tax or view tax configurations?

Respond with a JSON object:
{
    "interacted_with_invoice_form": true/false,
    "manipulated_line_items": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible in the frames"
}
"""

def verify_create_invoice(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read exported result JSON from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_invoice_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []

    # 2. Database Structure Checks
    if not result.get("invoice_found"):
        feedback_parts.append("❌ Invoice 'INV-2024-GREENFIELD' not found in database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append("✅ Invoice record exists")
    inv = result.get("invoice", {})
    
    # Check Timestamps (Anti-Gaming)
    task_start = result.get("task_start_time", 0)
    created_time_str = inv.get("createdtime", "2000-01-01 00:00:00")
    try:
        created_dt = datetime.strptime(created_time_str, "%Y-%m-%d %H:%M:%S")
        created_ts = created_dt.timestamp()
        if created_ts > task_start:
            feedback_parts.append("✅ Invoice created during task session")
        else:
            feedback_parts.append("❌ Invoice created before task started (Anti-gaming check failed)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    except:
        pass # Allow pass if parsing fails strictly on format

    # Check Org and Contact links
    if inv.get("accountname") == metadata.get("expected_organization"):
        score += 15
        feedback_parts.append("✅ Organization linked correctly")
    else:
        feedback_parts.append(f"❌ Organization mismatch: expected {metadata.get('expected_organization')}")

    if inv.get("contactname") == metadata.get("expected_contact"):
        score += 10
        feedback_parts.append("✅ Contact linked correctly")
    else:
        feedback_parts.append(f"❌ Contact mismatch: expected {metadata.get('expected_contact')}")

    if inv.get("duedate") == metadata.get("expected_due_date"):
        score += 10
        feedback_parts.append("✅ Due date is correct")
    else:
        feedback_parts.append(f"❌ Due date mismatch")

    # Check Line Items
    line_items = result.get("line_items", [])
    has_mower = False
    has_irrigation = False
    
    for item in line_items:
        if item.get("productname") == metadata["line_item_1"]["name"]:
            if item.get("quantity") == metadata["line_item_1"]["qty"] and item.get("listprice") == metadata["line_item_1"]["price"]:
                has_mower = True
                score += 15
        elif item.get("productname") == metadata["line_item_2"]["name"]:
            if item.get("quantity") == metadata["line_item_2"]["qty"] and item.get("listprice") == metadata["line_item_2"]["price"]:
                has_irrigation = True
                score += 15
                
    if has_mower: feedback_parts.append("✅ Commercial Lawn Mower line item correct")
    else: feedback_parts.append("❌ Mower line item missing or incorrect values")
    
    if has_irrigation: feedback_parts.append("✅ Irrigation Control System line item correct")
    else: feedback_parts.append("❌ Irrigation line item missing or incorrect values")

    # Check Tax and Totals
    # Tolerate minor floating point diffs
    subtotal = float(inv.get("subtotal", 0.0))
    total = float(inv.get("total", 0.0))
    calculated_tax = total - subtotal
    
    expected_tax = metadata.get("expected_tax")
    expected_total = metadata.get("expected_total")
    
    if abs(calculated_tax - expected_tax) < 2.00:
        score += 15
        feedback_parts.append("✅ Sales tax applied correctly (~8.25%)")
    else:
        feedback_parts.append(f"❌ Tax incorrect: Subtotal=${subtotal:.2f}, Total=${total:.2f}, Diff=${calculated_tax:.2f} (Expected tax: ${expected_tax:.2f})")

    if abs(total - expected_total) < 2.00:
        score += 10
        feedback_parts.append(f"✅ Grand total correct (${total:.2f})")
    else:
        feedback_parts.append(f"❌ Grand total incorrect (${total:.2f})")

    # 3. VLM Workflow Check
    vlm_passed = False
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if frames or final:
                images = frames + [final] if final else frames
                vlm_resp = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
                
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("interacted_with_invoice_form") and parsed.get("manipulated_line_items"):
                        vlm_passed = True
                        feedback_parts.append("✅ VLM confirmed CRM interaction workflow")
                    else:
                        feedback_parts.append("⚠️ VLM could not confirm proper CRM interaction workflow")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            
    # Success threshold: Require core database requirements (at least 60 points) AND VLM check if available
    key_criteria_met = (score >= 60 and (not query_vlm or vlm_passed))
    passed = bool(key_criteria_met and result.get("invoice_found"))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }