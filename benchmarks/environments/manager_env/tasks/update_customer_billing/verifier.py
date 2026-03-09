#!/usr/bin/env python3
"""
Verifier for update_customer_billing task.

Criteria:
1. Customer 'Ernst Handel' must exist (10 pts)
2. Billing address must contain 'Musterstraße 42', 'Wien 1010', 'Austria' (30 pts)
3. Old address 'Kirchgasse 6' must be gone (10 pts)
4. Email must be 'e.handel@ernsthandel.at' (25 pts)
5. Old email must be gone (5 pts)
6. Customer name must still be 'Ernst Handel' (no rename) (10 pts)
7. No duplicate customers created (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_customer_billing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_address_parts = metadata.get('expected_address_parts', ["Musterstraße 42", "Wien 1010", "Austria"])
    expected_email = metadata.get('expected_email', "e.handel@ernsthandel.at")
    forbidden_address_parts = metadata.get('forbidden_address_parts', ["Kirchgasse 6", "Graz 8010"])
    forbidden_email = metadata.get('forbidden_email', "ernst.handel@example.at")

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Customer Exists & No Duplicates
    customer_found = result.get('customer_found', False)
    ernst_count = result.get('ernst_count', 0)
    
    if customer_found:
        score += 10
        feedback.append("Customer 'Ernst Handel' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Customer 'Ernst Handel' not found."}

    if ernst_count == 1:
        score += 10
        feedback.append("No duplicate customers found.")
    elif ernst_count > 1:
        feedback.append(f"FAIL: Found {ernst_count} customers named 'Ernst Handel'. Duplicate created?")
    else:
        feedback.append("FAIL: Customer count error.")

    # Parse HTML content for specific fields
    html_content = result.get('customer_details_html', "")
    if not html_content:
        return {"passed": False, "score": score, "feedback": "Failed to retrieve customer details."}

    # 2. Check Address Updates (30 pts)
    # We check if ALL expected parts are present in the HTML
    address_match_count = sum(1 for part in expected_address_parts if part in html_content)
    if address_match_count == len(expected_address_parts):
        score += 30
        feedback.append("Billing address updated correctly.")
    elif address_match_count > 0:
        score += 10 # Partial credit
        feedback.append(f"Billing address partially updated ({address_match_count}/{len(expected_address_parts)} parts found).")
    else:
        feedback.append("Billing address NOT updated.")

    # 3. Check Old Address Removal (10 pts)
    old_address_present = any(part in html_content for part in forbidden_address_parts)
    if not old_address_present:
        score += 10
        feedback.append("Old billing address removed.")
    else:
        feedback.append("FAIL: Old billing address still present (did you append instead of replace?).")

    # 4. Check Email Update (25 pts)
    if expected_email in html_content:
        score += 25
        feedback.append("Email updated correctly.")
    else:
        feedback.append(f"Email NOT updated. Expected: {expected_email}")

    # 5. Check Old Email Removal (5 pts)
    if forbidden_email not in html_content:
        score += 5
        feedback.append("Old email removed.")
    else:
        feedback.append("FAIL: Old email still present.")

    # 6. Check Name Preservation (10 pts)
    # We verified the record was found via the name "Ernst Handel" in the export script.
    # The export script looked for hrefs near "Ernst Handel". 
    # If the name was changed, the export script might have failed to find the link or the count would be 0.
    if "Ernst Handel" in html_content:
        score += 10
        feedback.append("Customer name preserved.")
    else:
        feedback.append("FAIL: Customer name appears changed or missing in details.")

    passed = score >= 60 and customer_found and (address_match_count == len(expected_address_parts)) and (expected_email in html_content)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }