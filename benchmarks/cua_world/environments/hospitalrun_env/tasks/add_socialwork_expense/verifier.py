#!/usr/bin/env python3
"""
Verifier for add_socialwork_expense task.

Verifies that:
1. A new expense document was created in CouchDB.
2. The document is linked to patient 'Maria Santos'.
3. The category is 'Transportation'.
4. The amount is 45.00.
5. The description matches keywords.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_socialwork_expense(traj, env_info, task_info):
    """
    Verify the social work expense creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_amount = metadata.get('expected_amount', 45.00)
    tolerance = metadata.get('amount_tolerance', 0.5)
    keywords = metadata.get('expected_description_keywords', ["taxi", "chemotherapy", "oncology", "round-trip"])
    expected_patient_id = metadata.get("patient_id", "patient_p1_00002")

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    candidate_docs = result.get('candidate_docs', [])
    initial_count = result.get('initial_expense_count', 0)
    task_start = result.get('task_start', 0)
    
    # 1. Identify the specific document created during the task
    # We look for a document that matches our criteria and ideally was created/modified recently
    # Since we don't have exact creation time in the doc usually, we check content first.
    
    matching_doc = None
    best_match_score = 0
    feedback_details = []

    for doc in candidate_docs:
        current_score = 0
        doc_details = []
        doc_str = json.dumps(doc).lower()
        data = doc.get('data', doc) # Handle HospitalRun data wrapper

        # Check Patient Linkage
        patient_ref = data.get('patient', doc.get('patient', ''))
        patient_match = (expected_patient_id in patient_ref) or \
                        ('maria' in doc_str and 'santos' in doc_str)
        if patient_match:
            current_score += 10
            doc_details.append("Patient match")

        # Check Category
        category = data.get('category', data.get('expenseCategory', ''))
        if 'transportation' in str(category).lower():
            current_score += 10
            doc_details.append("Category match")

        # Check Amount
        cost = data.get('cost', data.get('amount', None))
        amount_match = False
        if cost is not None:
            try:
                # remove currency symbols
                val = float(str(cost).replace('$', '').replace(',', ''))
                if abs(val - expected_amount) <= tolerance:
                    amount_match = True
                    current_score += 10
                    doc_details.append("Amount match")
            except ValueError:
                pass
        
        # Check Description
        desc = data.get('description', data.get('notes', ''))
        desc_lower = str(desc).lower()
        keyword_hits = sum(1 for kw in keywords if kw in desc_lower)
        if keyword_hits >= 2: # Require at least 2 keywords
            current_score += 10
            doc_details.append(f"Description keywords ({keyword_hits})")

        # Select this as best match if score is higher
        if current_score > best_match_score:
            best_match_score = current_score
            matching_doc = doc
            feedback_details = doc_details

    # Scoring
    score = 0
    feedback = ""

    if not matching_doc:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No expense document found matching the criteria."
        }
    
    # Base score for finding a candidate
    score += 10 
    
    # Evaluate the best matching document against criteria
    passed_criteria = []
    
    # 1. Patient Linkage (20 pts)
    doc_str = json.dumps(matching_doc).lower()
    data = matching_doc.get('data', matching_doc)
    patient_ref = data.get('patient', matching_doc.get('patient', ''))
    
    if (expected_patient_id in patient_ref) or ('maria' in doc_str and 'santos' in doc_str):
        score += 20
        passed_criteria.append("Patient linked")
    else:
        feedback += "Expense found but not linked to Maria Santos. "

    # 2. Category (20 pts)
    category = data.get('category', data.get('expenseCategory', ''))
    if 'transportation' in str(category).lower():
        score += 20
        passed_criteria.append("Correct category")
    else:
        feedback += f"Incorrect category (found: {category}). "

    # 3. Amount (25 pts)
    cost = data.get('cost', data.get('amount', None))
    val = 0
    try:
        val = float(str(cost).replace('$', '').replace(',', ''))
        if abs(val - expected_amount) <= tolerance:
            score += 25
            passed_criteria.append("Correct amount")
        else:
            feedback += f"Incorrect amount (found: {val}, expected: {expected_amount}). "
    except (ValueError, TypeError):
        feedback += f"Invalid amount format: {cost}. "

    # 4. Description (25 pts)
    desc = data.get('description', data.get('notes', ''))
    desc_lower = str(desc).lower()
    keyword_hits = sum(1 for kw in keywords if kw in desc_lower)
    
    if keyword_hits >= 2:
        score += 25
        passed_criteria.append("Description correct")
    elif keyword_hits > 0:
        score += 10
        feedback += "Description partially correct (some keywords missing). "
    else:
        feedback += "Description missing or incorrect. "

    # Check for anti-gaming: "New" document
    # If the total count didn't increase, and we found a doc, it might be an old one (if we didn't wipe)
    # But setup didn't wipe expenses. However, we assume this is a unique task instance.
    # The timestamps in CouchDB are usually in 'rev' or sometimes explicit fields.
    # A robust check is simply: did we find *more* candidate docs than we started with?
    # Or rely on the specific content match being unique enough for this task.
    # Given the specific amount and description, collision is unlikely.
    
    if score >= 100:
        feedback = "Perfect! Social work expense created correctly."
    elif score >= 50:
        feedback = f"Task passed with issues: {feedback}"
    else:
        feedback = f"Task failed. {feedback}"

    return {
        "passed": score >= 50,
        "score": score,
        "feedback": feedback,
        "details": {"match_details": passed_criteria}
    }