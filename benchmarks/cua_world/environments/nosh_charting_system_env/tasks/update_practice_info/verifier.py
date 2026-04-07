#!/usr/bin/env python3
"""
Verifier for update_practice_info task.

Checks if the agent correctly updated the practice contact details 
while preserving the practice name and state.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_practice_info(traj, env_info, task_info):
    """
    Verify practice info update.
    
    Scoring:
    - Address fields (Street, City, Zip): 40 pts
    - Contact fields (Phone, Fax, Email): 40 pts
    - Name & State Preserved: 15 pts
    - Anti-gaming (Database changed): 5 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Expected Values from Metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {
        "street_address1": "250 Elm Street, Suite 300",
        "city": "Northampton",
        "zip": "01060",
        "phone": "413-555-9876",
        "fax": "413-555-9877",
        "email": "office@hillsidefm.com"
    })
    
    preserved = metadata.get('preserved_values', {
        "practice_name": "Hillside Family Medicine",
        "state": "MA"
    })

    # 2. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze Results
    actual = result.get('practice_info', {})
    db_changed = result.get('db_changed', False)
    
    score = 0
    feedback_parts = []
    
    # Check 1: Address Fields (Total 40)
    addr_score = 0
    # Street (15)
    if actual.get('street_address1', '').strip() == expected['street_address1']:
        addr_score += 15
    else:
        feedback_parts.append(f"Address incorrect (got '{actual.get('street_address1')}')")
        
    # City (15)
    if actual.get('city', '').strip().lower() == expected['city'].lower():
        addr_score += 15
    else:
        feedback_parts.append(f"City incorrect (got '{actual.get('city')}')")
        
    # Zip (10)
    if actual.get('zip', '').strip() == expected['zip']:
        addr_score += 10
    else:
        feedback_parts.append(f"Zip incorrect (got '{actual.get('zip')}')")
    
    score += addr_score

    # Check 2: Contact Fields (Total 40)
    contact_score = 0
    # Phone (15)
    if actual.get('phone', '').strip() == expected['phone']:
        contact_score += 15
    else:
        feedback_parts.append(f"Phone incorrect (got '{actual.get('phone')}')")
        
    # Fax (10)
    if actual.get('fax', '').strip() == expected['fax']:
        contact_score += 10
    else:
        feedback_parts.append(f"Fax incorrect (got '{actual.get('fax')}')")
        
    # Email (15)
    if actual.get('email', '').strip().lower() == expected['email'].lower():
        contact_score += 15
    else:
        feedback_parts.append(f"Email incorrect (got '{actual.get('email')}')")
        
    score += contact_score

    # Check 3: Preservation (Total 15)
    preservation_score = 0
    # Name (10) - Critical for anti-gaming (don't overwrite whole record)
    if actual.get('practice_name', '').strip() == preserved['practice_name']:
        preservation_score += 10
    else:
        feedback_parts.append(f"CRITICAL: Practice Name changed unexpectedly to '{actual.get('practice_name')}'")
        
    # State (5)
    if actual.get('state', '').strip() == preserved['state']:
        preservation_score += 5
    else:
        feedback_parts.append(f"State changed unexpectedly to '{actual.get('state')}'")
        
    score += preservation_score

    # Check 4: Anti-Gaming / Activity (5)
    if db_changed:
        score += 5
    else:
        feedback_parts.append("No changes detected in database")

    # Final Evaluation
    # Pass if Score >= 70 AND Critical Name Preserved AND Address/Phone mostly correct
    passed = score >= 70 and (actual.get('practice_name') == preserved['practice_name'])
    
    final_feedback = "Task Completed Successfully." if passed else "Task Failed."
    if feedback_parts:
        final_feedback += " Issues: " + ", ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback,
        "details": {
            "actual": actual,
            "expected": expected
        }
    }