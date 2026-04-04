#!/usr/bin/env python3
"""
Verifier for configure_tax_inclusive_pricing task.

Uses a combination of:
1. File verification (receipt screenshot existence and timestamp)
2. System state verification (data files modified, registry settings if captured)
3. VLM verification (reading the math from the receipt screenshot)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_tax_inclusive_pricing(traj, env_info, task_info):
    """
    Verify that the tax inclusive pricing was configured and tested correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Receipt Screenshot
    receipt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    receipt_path_in_container = result.get('receipt_path')
    receipt_retrieved = False
    if result.get('receipt_exists'):
        try:
            copy_from_env(receipt_path_in_container, receipt_temp.name)
            receipt_retrieved = True
        except Exception as e:
            logger.warning(f"Could not copy receipt image: {e}")

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Receipt file exists and was created during task (20 pts)
    if result.get('receipt_exists'):
        if result.get('receipt_created_during_task'):
            score += 20
            feedback_parts.append("Receipt screenshot saved during task.")
        else:
            score += 5
            feedback_parts.append("Receipt screenshot exists but old timestamp.")
    else:
        feedback_parts.append("No receipt screenshot found.")

    # Criterion 2: Data/Settings modification (20 pts)
    # Checks if application data was written or registry changed
    if result.get('data_modified'):
        score += 20
        feedback_parts.append("Application data/settings modified.")
    else:
        feedback_parts.append("No evidence of data modification.")

    # Criterion 3: Registry Check (Bonus/Confirmation)
    # If the export script successfully detected the registry key
    reg_setting = result.get('registry_tax_inclusive')
    if reg_setting is True:
        score += 10
        feedback_parts.append("Registry confirms Tax Inclusive enabled.")
    elif reg_setting is False:
        feedback_parts.append("Registry indicates Tax Inclusive is DISABLED.")

    # Criterion 4: VLM Verification of Receipt Math (50 pts)
    # We need to check if Total = 120.00 and Tax = 20.00
    vlm_passed = False
    if receipt_retrieved and query_vlm:
        prompt = (
            "Analyze this POS receipt or transaction screen.\n"
            "Extract the following values:\n"
            "1. The Grand Total amount.\n"
            "2. The Tax (or VAT) amount.\n"
            "3. Any text indicating 'Tax Inclusive' or 'Includes Tax'.\n\n"
            "Does the receipt show a Total of roughly 120.00 and a Tax component of roughly 20.00?\n"
            "Note: If Tax is added on top, the total would be 144.00. We want 120.00 total.\n"
            "Respond in JSON: {'total': 'value', 'tax': 'value', 'is_inclusive': true/false}"
        )
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=receipt_temp.name)
            if vlm_response.get('success'):
                data = vlm_response.get('parsed', {})
                
                # Check Total (Allow small OCR variance)
                total_str = str(data.get('total', '0')).replace('$','').replace('£','')
                tax_str = str(data.get('tax', '0')).replace('$','').replace('£','')
                
                try:
                    total_val = float(total_str)
                    tax_val = float(tax_str)
                    
                    if 119.0 <= total_val <= 121.0:
                        score += 25
                        feedback_parts.append(f"VLM verified Total: {total_val} (Target: 120.00)")
                        
                        if 19.0 <= tax_val <= 21.0:
                            score += 25
                            feedback_parts.append(f"VLM verified Tax: {tax_val} (Target: 20.00)")
                            vlm_passed = True
                        else:
                            feedback_parts.append(f"VLM found wrong Tax: {tax_val} (Expected ~20.00)")
                    elif 143.0 <= total_val <= 145.0:
                        feedback_parts.append("VLM found Total ~144.00. This implies Tax Added (Exclusive), not Inclusive.")
                    else:
                        feedback_parts.append(f"VLM found unexpected Total: {total_val}")
                        
                except ValueError:
                    feedback_parts.append("VLM could not parse numbers from receipt.")
            else:
                feedback_parts.append("VLM query failed.")
        except Exception as e:
            feedback_parts.append(f"VLM error: {e}")

    # Cleanup
    if os.path.exists(receipt_temp.name):
        os.unlink(receipt_temp.name)

    # Final Pass Logic
    # Pass if score >= 80 OR (Receipt Exists + VLM Math Correct)
    passed = score >= 80 or (result.get('receipt_created_during_task') and vlm_passed)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }