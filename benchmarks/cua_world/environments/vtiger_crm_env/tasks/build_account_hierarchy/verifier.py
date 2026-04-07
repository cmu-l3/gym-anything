#!/usr/bin/env python3
"""
Verifier for build_account_hierarchy task.
Validates the creation and precise linkage of the parent organization,
regional subsidiaries, and key contact via relational IDs in the database.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_account_hierarchy(traj, env_info, task_info):
    """
    Verify the multi-level organization hierarchy.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_industry = metadata.get('parent_industry', 'Finance')
    expected_revenue = str(metadata.get('parent_revenue', '150000000'))

    # Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/build_hierarchy_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    parent = result.get('parent', {})
    sub1 = result.get('sub1', {})
    sub2 = result.get('sub2', {})
    contact = result.get('contact', {})
    
    initial_max_crmid = result.get('initial_max_crmid', 0)
    
    parent_id = str(parent.get('id', '0'))
    
    # 1. Parent Organization Verification (15 pts) + Fields (10 pts)
    if parent.get('found', False):
        score += 15
        feedback_parts.append("✅ Parent organization found")
        
        # Strip trailing formatting commonly applied to revenue (e.g., .00)
        actual_rev = str(parent.get('revenue', '0')).split('.')[0]
        actual_ind = parent.get('industry', '')
        
        if actual_ind == expected_industry and actual_rev == expected_revenue:
            score += 10
            feedback_parts.append("✅ Parent industry & revenue correct")
        else:
            feedback_parts.append(f"❌ Parent fields mismatch (Ind: {actual_ind}, Rev: {actual_rev})")
    else:
        feedback_parts.append("❌ Parent organization missing")

    # 2. Subsidiary 1 Verification (10 pts) + Linking (15 pts)
    if sub1.get('found', False):
        score += 10
        feedback_parts.append("✅ Subsidiary 1 found")
        
        if parent_id != '0' and str(sub1.get('parentid', '0')) == parent_id:
            score += 15
            feedback_parts.append("✅ Subsidiary 1 properly linked to Parent")
        else:
            feedback_parts.append("❌ Subsidiary 1 NOT linked to Parent")
    else:
        feedback_parts.append("❌ Subsidiary 1 missing")

    # 3. Subsidiary 2 Verification (10 pts) + Linking (15 pts)
    if sub2.get('found', False):
        score += 10
        feedback_parts.append("✅ Subsidiary 2 found")
        
        if parent_id != '0' and str(sub2.get('parentid', '0')) == parent_id:
            score += 15
            feedback_parts.append("✅ Subsidiary 2 properly linked to Parent")
        else:
            feedback_parts.append("❌ Subsidiary 2 NOT linked to Parent")
    else:
        feedback_parts.append("❌ Subsidiary 2 missing")

    # 4. Contact Verification (5 pts) + Linking (5 pts)
    if contact.get('found', False):
        score += 5
        feedback_parts.append("✅ Contact Elias Vance found")
        
        if parent_id != '0' and str(contact.get('accountid', '0')) == parent_id:
            score += 5
            feedback_parts.append("✅ Contact properly linked to Parent")
        else:
            feedback_parts.append("❌ Contact NOT linked to Parent")
    else:
        feedback_parts.append("❌ Contact missing")

    # 5. Anti-gaming check (Session Validity) - ensures items were created during task
    # We check that every found item has an ID strictly greater than the initial max ID.
    valid_session = True
    created_any = False
    
    for entity_name, entity in [("Parent", parent), ("Sub1", sub1), ("Sub2", sub2), ("Contact", contact)]:
        if entity.get('found', False):
            created_any = True
            e_id = int(entity.get('id', '0'))
            if e_id <= initial_max_crmid:
                valid_session = False
                feedback_parts.append(f"⚠️ Anti-gaming flag: {entity_name} existed before task started.")

    if valid_session and created_any:
        # Give remaining 10 points for a fully valid non-gamed session
        score += 10
        feedback_parts.append("✅ Temporal validity verified (no pre-existing records used)")

    # Compute final outcome
    # Require at least parent and one properly linked sub, plus pass threshold of 70
    passed = score >= 70 and parent.get('found', False) and (
        str(sub1.get('parentid', '0')) == parent_id or str(sub2.get('parentid', '0')) == parent_id
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }