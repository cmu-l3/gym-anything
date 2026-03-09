#!/usr/bin/env python3
"""Verifier for Brand PDF Invoices task in Magento."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_brand_pdf_invoices(traj, env_info, task_info):
    """
    Verify branding configuration and invoice creation.
    
    Criteria:
    1. Logo for PDF is configured (contains uploaded filename) (20 pts)
    2. Logo for HTML is configured (contains uploaded filename) (20 pts)
    3. Address is configured matches expected text exactly (20 pts)
       - Partial credit (10 pts) if address has correct content but slight formatting diffs
    4. A new invoice was created during the task session (30 pts)
    5. Anti-gaming: Invoice must be created AFTER config changes (implied by workflow, but we check task window)
    
    Pass threshold: 70 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_logo_filename = metadata.get('logo_filename', 'nestwell_logo.png')
    expected_address = metadata.get('expected_address', "NestWell Home Fulfillment\n123 Commerce Dr\nLos Angeles, CA 90001")
    
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/brand_pdf_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        # 1. Verify Logo Config
        # Magento stores logo path like "default/nestwell_logo.png" or "default/nestwell_logo_1.png"
        logo_val = result.get('logo_config_value', '')
        if logo_val and 'nestwell_logo' in logo_val:
            score += 20
            feedback_parts.append("PDF Logo configured correctly (20 pts)")
        elif logo_val:
            feedback_parts.append(f"PDF Logo set to '{logo_val}', expected filename containing 'nestwell_logo'")
        else:
            feedback_parts.append("PDF Logo not configured")
            
        # 2. Verify HTML Logo Config
        logo_html_val = result.get('logo_html_config_value', '')
        if logo_html_val and 'nestwell_logo' in logo_html_val:
            score += 20
            feedback_parts.append("HTML Logo configured correctly (20 pts)")
        elif logo_html_val:
            feedback_parts.append(f"HTML Logo set to '{logo_html_val}', expected filename containing 'nestwell_logo'")
        else:
            feedback_parts.append("HTML Logo not configured")
            
        # 3. Verify Address
        address_val = result.get('address_config_value', '').strip()
        expected_norm = expected_address.strip().replace('\r\n', '\n')
        actual_norm = address_val.replace('\r\n', '\n')
        
        if actual_norm == expected_norm:
            score += 20
            feedback_parts.append("Address configured exactly (20 pts)")
        elif "123 Commerce Dr" in actual_norm and "Los Angeles" in actual_norm:
            score += 10
            feedback_parts.append("Address matches content but has formatting differences (10 pts)")
        else:
            feedback_parts.append("Address text incorrect")
            
        # 4. Verify Invoice Creation
        invoice_created = result.get('invoice_created_during_task', False)
        if invoice_created:
            score += 30
            feedback_parts.append("New invoice created during task (30 pts)")
        else:
            feedback_parts.append("No invoice created during the task window")
            
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}