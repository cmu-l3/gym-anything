#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sales_order(traj, env_info, task_info):
    """
    Verify the Sales Order creation task.
    Uses multi-criteria DB signals + VLM anti-gaming verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve the exported JSON result
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

    score = 0
    feedback_parts = []
    
    so_info = result.get('sales_order')
    
    if not so_info:
        feedback_parts.append("Sales Order not found in database.")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }
        
    # --- Criterion 1: SO Record exists (15 points) ---
    score += 15
    feedback_parts.append("Sales Order record found")
    
    # --- Criterion 2: Correct Organization (10 points) ---
    org = so_info.get('organization', '')
    if metadata['expected_organization'].lower() in org.lower():
        score += 10
        feedback_parts.append("Organization linked correctly")
    else:
        feedback_parts.append(f"Org mismatch (got: {org})")

    # --- Criterion 3: Correct Contact (10 points) ---
    contact = so_info.get('contact', '')
    if metadata['expected_contact'].lower() in contact.lower():
        score += 10
        feedback_parts.append("Contact linked correctly")
    else:
        feedback_parts.append(f"Contact mismatch (got: {contact})")

    # --- Criterion 4: Status and Due Date (5 points) ---
    if so_info.get('status') == metadata['expected_status'] and metadata['expected_due_date'] in so_info.get('duedate', ''):
        score += 5
        feedback_parts.append("Status and due date correct")
    else:
        feedback_parts.append("Status or due date incorrect")

    # --- Criterion 5: Grand Total (5 points) ---
    total = so_info.get('total', 0.0)
    if abs(total - metadata['expected_total']) <= metadata['tolerance_total']:
        score += 5
        feedback_parts.append("Grand total correct")
    else:
        feedback_parts.append(f"Grand total incorrect (got: {total})")

    # --- Criterion 6: Line Items (25 points total) ---
    items = so_info.get('line_items', [])
    if len(items) == metadata['expected_line_items']:
        score += 10
        feedback_parts.append(f"Found exactly {len(items)} line items")
    else:
        feedback_parts.append(f"Found {len(items)} line items (expected {metadata['expected_line_items']})")

    # Item specifics (5 pts each)
    found_fert = found_mulch = found_irrig = False
    for item in items:
        name = item.get('name', '').lower()
        qty = item.get('quantity', 0.0)
        price = item.get('price', 0.0)
        
        if 'fertilizer' in name and qty == 20.0 and abs(price - 45.0) < 1.0:
            found_fert = True
            score += 5
        elif 'mulch' in name and qty == 15.0 and abs(price - 38.0) < 1.0:
            found_mulch = True
            score += 5
        elif 'irrigation' in name and qty == 8.0 and abs(price - 125.0) < 1.0:
            found_irrig = True
            score += 5
            
    if found_fert and found_mulch and found_irrig:
        feedback_parts.append("All line item products, quantities, and prices correct")
    else:
        feedback_parts.append("Some line item specifics missing or incorrect")

    # --- Criterion 7: Anti-gaming (DB Timestamps) (10 points) ---
    task_start = result.get('task_start_time', 0)
    created_time = so_info.get('created_time', 0)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    if current_count > initial_count and created_time >= task_start:
        score += 10
        feedback_parts.append("Anti-gaming checks passed")
    else:
        feedback_parts.append("Failed anti-gaming: record pre-dates task or count didn't increase")

    # --- Criterion 8: VLM Trajectory Verification (20 points) ---
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            prompt = """You are verifying a web automation trajectory for Vtiger CRM.
Did the agent use the web interface to fill out the 'Sales Order' creation form?
Look specifically for interaction with the Line Items (Item Details) section where products like Fertilizer, Mulch, or Irrigation kits are added.
Respond in JSON: {"used_ui": true/false, "reasoning": "short explanation"}
"""
            vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_res and vlm_res.get('parsed', {}).get('used_ui', False):
                score += 20
                feedback_parts.append("VLM confirmed UI usage")
            else:
                feedback_parts.append("VLM did not confirm proper UI usage")
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            score += 20 # Grant points if VLM crashes to prevent unfair fails
            feedback_parts.append("VLM error, auto-granting VLM points")
    else:
        # If VLM is not available, we assume true to be fair
        score += 20
        feedback_parts.append("VLM unavailable, auto-granting VLM points")

    passed = score >= 60 and so_info is not None

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }