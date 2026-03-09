#!/usr/bin/env python3
"""
Verifier for add_patient_family_info task.

Criteria:
1. Document exists in CouchDB containing "Carlos Santos" (25 pts)
2. Document is linked to patient Maria Santos (15 pts)
3. Fields match expectations:
   - Name: Carlos Santos (15 pts)
   - Relationship: Spouse (10 pts)
   - Age: 57 (10 pts)
   - Sex: Male (10 pts)
   - Education: College (5 pts)
   - Income: 45000 (5 pts)
4. Anti-gaming: Document is new (count increased or new _rev) (5 pts)

Total: 100 pts
Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_patient_family_info(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # Extract data
    query_result = result.get('query_result', {})
    matches = query_result.get('matches', [])
    initial_count = int(result.get('initial_db_count', 0))
    current_count = int(result.get('current_db_count', 0))
    
    # 1. Check if document exists
    if not matches:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No database document found containing 'Carlos Santos'. Task failed."
        }
    
    score += 25
    feedback_parts.append("Family document created")
    
    # We'll analyze the best matching document
    # If multiple exist, pick the one that looks most correct
    best_doc = matches[0]
    
    # 2. Check linkage to Maria Santos
    doc_str = json.dumps(best_doc).lower()
    patient_linked = False
    
    # Check for direct ID reference or embedded name
    if "patient_p1_001" in doc_str or "p00001" in doc_str:
        patient_linked = True
    elif "maria" in doc_str and "santos" in doc_str:
        # In HospitalRun, sometimes family info is embedded in the patient doc itself
        # or references the patient by name/id
        patient_linked = True
        
    if patient_linked:
        score += 15
        feedback_parts.append("Linked to correct patient")
    else:
        feedback_parts.append("Link to Maria Santos not found")
        
    # 3. Verify Fields
    # Helper to check deeply nested fields
    def get_val(doc, keys):
        for k in keys:
            # Check top level
            if k in doc: return doc[k]
            # Check inside 'data' wrapper
            if 'data' in doc and isinstance(doc['data'], dict) and k in doc['data']:
                return doc['data'][k]
        return None

    # Name Check (Already validated existence, but check specific field)
    name = get_val(best_doc, ['name', 'fullName', 'familyMemberName'])
    if not name and 'carlos' in doc_str: name = "Carlos Santos" # Fallback if found in raw text
    
    if name and 'carlos' in str(name).lower() and 'santos' in str(name).lower():
        score += 15
        feedback_parts.append("Name correct")
    
    # Relationship Check
    rel = get_val(best_doc, ['relationship', 'relation', 'relationToPatient'])
    if rel and 'spouse' in str(rel).lower():
        score += 10
        feedback_parts.append("Relationship correct")
    else:
        feedback_parts.append(f"Relationship mismatch (found: {rel})")
        
    # Age Check
    age = get_val(best_doc, ['age', 'memberAge'])
    if age and str(age) == '57':
        score += 10
        feedback_parts.append("Age correct")
    else:
        feedback_parts.append(f"Age mismatch (found: {age})")
        
    # Sex Check
    sex = get_val(best_doc, ['sex', 'gender'])
    if sex and str(sex).lower() in ['male', 'm']:
        score += 10
        feedback_parts.append("Sex correct")
    else:
        feedback_parts.append("Sex mismatch")
        
    # Education Check
    edu = get_val(best_doc, ['education', 'educationLevel'])
    if edu and 'college' in str(edu).lower():
        score += 5
        feedback_parts.append("Education correct")
        
    # Income Check
    income = get_val(best_doc, ['income', 'annualIncome'])
    if income and '45000' in str(income).replace(',', ''):
        score += 5
        feedback_parts.append("Income correct")
        
    # 4. Anti-gaming: Check for newness
    # Either document count increased OR the doc has a revision starting with '1-'
    # If the user edited an existing doc, rev would be higher, but count wouldn't change.
    # We want a NEW entry.
    
    is_new = False
    rev = best_doc.get('_rev', '')
    if rev.startswith('1-'):
        is_new = True
    elif current_count > initial_count:
        is_new = True
        
    if is_new:
        score += 5
        feedback_parts.append("New record created")
    else:
        feedback_parts.append("Record appears pre-existing (anti-gaming penalty)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }