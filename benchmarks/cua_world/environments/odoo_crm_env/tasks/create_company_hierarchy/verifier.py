#!/usr/bin/env python3
"""
Verifier for create_company_hierarchy task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_company_hierarchy(traj, env_info, task_info):
    """
    Verifies that the company hierarchy was created correctly in Odoo.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve the result JSON from the container
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

    records = result.get("records", {})
    task_start = result.get("task_start", 0)

    score = 0
    feedback_parts = []
    
    # Helper for checking fields
    def check_field(record, field, value, partial=False):
        if not record: return False
        rec_val = str(record.get(field, '') or '')
        if partial:
            return str(value).lower() in rec_val.lower()
        return str(value).lower() == rec_val.lower()

    # --- 1. Parent Company: Nexus Global Industries (20 pts) ---
    parent = records.get("Nexus Global Industries")
    parent_id = parent['id'] if parent else None
    
    if parent:
        if parent.get('is_company'):
            score += 10
            feedback_parts.append("Parent company created correctly")
        else:
            score += 5
            feedback_parts.append("Parent created but not as Company")
            
        # Details check
        details_score = 0
        if check_field(parent, 'street', 'Park Avenue', True): details_score += 2
        if check_field(parent, 'city', 'New York', True): details_score += 2
        if check_field(parent, 'zip', '10022', True): details_score += 1
        if check_field(parent, 'phone', '212', True): details_score += 2
        if check_field(parent, 'website', 'nexusglobal', True): details_score += 2
        if check_field(parent, 'country_id', 'United States', True): details_score += 1
        
        score += min(details_score, 10)
    else:
        feedback_parts.append("Parent company not found")

    # --- 2. Subsidiary: Europe (17 pts) ---
    europe = records.get("Nexus Global - Europe")
    europe_id = europe['id'] if europe else None
    
    if europe:
        # Check hierarchy
        e_parent = europe.get('parent_id') # [id, name]
        e_parent_id = e_parent[0] if isinstance(e_parent, list) and e_parent else None
        
        if parent_id and e_parent_id == parent_id:
            score += 12
            feedback_parts.append("Europe subsidiary linked correctly")
        elif e_parent_id:
            score += 6
            feedback_parts.append("Europe subsidiary has wrong parent")
        else:
            score += 4
            feedback_parts.append("Europe subsidiary missing parent")
            
        # Address check
        addr_score = 0
        if check_field(europe, 'street', 'Moorgate', True): addr_score += 2
        if check_field(europe, 'city', 'London', True): addr_score += 2
        if check_field(europe, 'zip', 'EC2R', True): addr_score += 1
        score += min(addr_score, 5)
    else:
        feedback_parts.append("Europe subsidiary not found")

    # --- 3. Subsidiary: APAC (17 pts) ---
    apac = records.get("Nexus Global - Asia Pacific")
    apac_id = apac['id'] if apac else None
    
    if apac:
        # Check hierarchy
        a_parent = apac.get('parent_id')
        a_parent_id = a_parent[0] if isinstance(a_parent, list) and a_parent else None
        
        if parent_id and a_parent_id == parent_id:
            score += 12
            feedback_parts.append("APAC subsidiary linked correctly")
        elif a_parent_id:
            score += 6
            feedback_parts.append("APAC subsidiary has wrong parent")
        else:
            score += 4
            feedback_parts.append("APAC subsidiary missing parent")
            
        # Address check
        addr_score = 0
        if check_field(apac, 'street', 'Nihonbashi', True): addr_score += 2
        if check_field(apac, 'city', 'Tokyo', True): addr_score += 2
        if check_field(apac, 'zip', '103', True): addr_score += 1
        score += min(addr_score, 5)
    else:
        feedback_parts.append("APAC subsidiary not found")

    # --- 4. Contact: Elena (21 pts) ---
    elena = records.get("Elena Rossi")
    if elena:
        # Check hierarchy
        el_parent = elena.get('parent_id')
        el_parent_id = el_parent[0] if isinstance(el_parent, list) and el_parent else None
        
        if europe_id and el_parent_id == europe_id:
            score += 12
            feedback_parts.append("Elena linked to Europe HQ")
        elif el_parent_id:
            score += 6
            feedback_parts.append("Elena has wrong parent company")
        else:
            score += 4
            feedback_parts.append("Elena missing company link")
            
        # Details
        det_score = 0
        if check_field(elena, 'function', 'VP', True): det_score += 3
        if check_field(elena, 'email', 'elena.rossi', True): det_score += 3
        if check_field(elena, 'phone', '7946', True): det_score += 3
        score += min(det_score, 9)
    else:
        feedback_parts.append("Elena Rossi not found")

    # --- 5. Contact: Kenji (21 pts) ---
    kenji = records.get("Kenji Tanaka")
    if kenji:
        # Check hierarchy
        k_parent = kenji.get('parent_id')
        k_parent_id = k_parent[0] if isinstance(k_parent, list) and k_parent else None
        
        if apac_id and k_parent_id == apac_id:
            score += 12
            feedback_parts.append("Kenji linked to APAC HQ")
        elif k_parent_id:
            score += 6
            feedback_parts.append("Kenji has wrong parent company")
        else:
            score += 4
            feedback_parts.append("Kenji missing company link")
            
        # Details
        det_score = 0
        if check_field(kenji, 'function', 'Director', True): det_score += 3
        if check_field(kenji, 'email', 'kenji.tanaka', True): det_score += 3
        if check_field(kenji, 'phone', '1234', True): det_score += 3
        score += min(det_score, 9)
    else:
        feedback_parts.append("Kenji Tanaka not found")

    # --- 6. Anti-Gaming Check (4 pts) ---
    # Check if at least one record was created after task start
    created_during = False
    for rec in [parent, europe, apac, elena, kenji]:
        if rec and rec.get('create_date'):
            # create_date format: '2024-03-01 12:00:00'
            try:
                c_date = datetime.strptime(rec['create_date'].split('.')[0], "%Y-%m-%d %H:%M:%S")
                if c_date.timestamp() > (task_start - 60): # 60s buffer
                    created_during = True
                    break
            except Exception:
                pass
    
    if created_during:
        score += 4
    else:
        feedback_parts.append("Records appear to pre-date task (anti-gaming)")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }