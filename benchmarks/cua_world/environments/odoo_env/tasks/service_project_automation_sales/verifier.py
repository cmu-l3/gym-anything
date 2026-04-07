#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_service_project_automation(traj, env_info, task_info):
    """
    Verifies that the agent correctly configured the service product,
    processed the sales order, auto-generated the project, 
    delivered the goods, and invoiced the order.
    """
    
    # 1. Load Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: Copy function not available"}

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
    feedback = []
    
    # Metadata for expectations
    meta = task_info.get('metadata', {})
    expected_total = meta.get('expected_total_untaxed', 4750.0)

    # --- Criterion 1: Product Configuration (25 pts) ---
    prod_config = result.get('product_config', {})
    if prod_config.get('exists'):
        # Check Type
        if prod_config.get('type') == 'service':
            score += 5
        else:
            feedback.append("Product type is not 'Service'.")

        # Check Invoice Policy
        if prod_config.get('invoice_policy') == 'order':
            score += 10
        else:
            feedback.append("Invoicing policy is not 'Ordered Quantities'.")

        # Check Service Tracking
        tracking = prod_config.get('service_tracking', '')
        # Accept 'task_in_project' (Task in new project) or 'project_only' (Create a project)
        # The prompt asks for "Create a task in a new project", which is 'task_in_project'
        if tracking in ['task_in_project', 'project_only']:
            score += 10
        else:
            feedback.append(f"Service tracking incorrect (Found: {tracking}). Should create Project/Task.")
    else:
        feedback.append("Service Product 'Logistics Site Audit' not found.")

    # --- Criterion 2: Sales Order Created & Lines (20 pts) ---
    so_status = result.get('so_status', {})
    if so_status.get('exists'):
        if so_status.get('state') in ['sale', 'done']:
            score += 10
        else:
            feedback.append("Sales Order created but not Confirmed.")
            
        if so_status.get('lines_correct'):
            score += 10
        else:
            feedback.append("Sales Order missing required products (Service + 5 Scanners).")
    else:
        feedback.append("Sales Order for Titanium Manufacturing not found.")
        # Critical failure path
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # --- Criterion 3: Project Automation (25 pts) ---
    proj_status = result.get('project_status', {})
    if proj_status.get('project_created') or proj_status.get('task_created'):
        score += 25
    else:
        feedback.append("Project/Task was NOT automatically generated from the Sales Order.")

    # --- Criterion 4: Physical Delivery (15 pts) ---
    del_status = result.get('delivery_status', {})
    if del_status.get('delivered'):
        score += 15
    else:
        feedback.append("Physical goods (Scanners) were not delivered (Picking not Done).")

    # --- Criterion 5: Invoicing (15 pts) ---
    inv_status = result.get('invoice_status', {})
    if inv_status.get('posted'):
        # Check amount with tolerance
        total = inv_status.get('total_amount', 0.0)
        # Allow 5% tolerance or tax diffs (though demo usually has standard taxes, we focus on untaxed or full amount)
        # Ideally setup checks untaxed, but verifying 'posted' is the main action
        if total >= expected_total * 0.9:
            score += 15
        else:
            score += 10 # Partial for posting but wrong amount
            feedback.append(f"Invoice posted but amount ${total} seems low (Expected ~$4750). Did you invoice both lines?")
    else:
        feedback.append("Invoice not created or not posted.")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }