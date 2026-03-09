#!/usr/bin/env python3
"""Verifier for Email Identity Configuration task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_identity_config(traj, env_info, task_info):
    """
    Verify Magento email configuration.
    
    Checks:
    1. Sales Representative identity (Name/Email)
    2. Customer Support identity (Name/Email)
    3. Order email sender & copy-to
    4. Invoice email sender
    5. Contact Us recipient & sender
    
    Pass threshold: 65 points
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    exp_sales_name = metadata.get('sales_name', 'NestWell Sales')
    exp_sales_email = metadata.get('sales_email', 'sales@nestwell.local')
    exp_support_name = metadata.get('support_name', 'NestWell Help Team')
    exp_support_email = metadata.get('support_email', 'support@nestwell.local')
    exp_manager_email = metadata.get('manager_email', 'manager@nestwell.local')
    exp_order_ident = metadata.get('order_identity', 'support')
    exp_invoice_ident = metadata.get('invoice_identity', 'sales')
    exp_contact_recip = metadata.get('contact_recipient', 'support@nestwell.local')
    exp_contact_sender = metadata.get('contact_sender', 'support')

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/email_config_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # 1. Sales Identity (15 pts)
    curr_sales_name = result.get('sales_name', '').strip()
    curr_sales_email = result.get('sales_email', '').strip()
    if curr_sales_name == exp_sales_name and curr_sales_email == exp_sales_email:
        score += 15
        feedback.append("Sales Identity defined correctly (15/15)")
    else:
        feedback.append(f"Sales Identity incorrect: Got '{curr_sales_name}'/'{curr_sales_email}'")

    # 2. Support Identity (15 pts)
    curr_support_name = result.get('support_name', '').strip()
    curr_support_email = result.get('support_email', '').strip()
    if curr_support_name == exp_support_name and curr_support_email == exp_support_email:
        score += 15
        feedback.append("Support Identity defined correctly (15/15)")
    else:
        feedback.append(f"Support Identity incorrect: Got '{curr_support_name}'/'{curr_support_email}'")

    # 3. Order Sender Assignment (20 pts)
    curr_order_ident = result.get('order_identity', '')
    if curr_order_ident == exp_order_ident:
        score += 20
        feedback.append("Order Sender assigned to Customer Support (20/20)")
    else:
        feedback.append(f"Order Sender incorrect: Got '{curr_order_ident}', expected '{exp_order_ident}'")

    # 4. Order Copy Email (15 pts)
    curr_copy_to = result.get('order_copy_to', '')
    if exp_manager_email in curr_copy_to:
        score += 15
        feedback.append("Order Copy-To email correct (15/15)")
    else:
        feedback.append(f"Order Copy-To missing '{exp_manager_email}'")

    # 5. Invoice Sender Assignment (15 pts)
    curr_invoice_ident = result.get('invoice_identity', '')
    if curr_invoice_ident == exp_invoice_ident:
        score += 15
        feedback.append("Invoice Sender assigned to Sales Representative (15/15)")
    else:
        feedback.append(f"Invoice Sender incorrect: Got '{curr_invoice_ident}', expected '{exp_invoice_ident}'")

    # 6. Contact Us Config (20 pts)
    curr_contact_recip = result.get('contact_recipient', '').strip()
    curr_contact_sender = result.get('contact_sender', '')
    
    contact_score = 0
    if curr_contact_recip == exp_contact_recip:
        contact_score += 10
    else:
        feedback.append(f"Contact Recipient incorrect: Got '{curr_contact_recip}'")
        
    if curr_contact_sender == exp_contact_sender:
        contact_score += 10
    else:
        feedback.append(f"Contact Sender incorrect: Got '{curr_contact_sender}'")
        
    if contact_score == 20:
        feedback.append("Contact Us config correct (20/20)")
    else:
        feedback.append(f"Contact Us config partial ({contact_score}/20)")
    
    score += contact_score

    # Final check
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }