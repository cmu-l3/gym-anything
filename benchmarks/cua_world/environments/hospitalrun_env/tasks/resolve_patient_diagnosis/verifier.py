#!/usr/bin/env python3
"""
Verifier for resolve_patient_diagnosis task.

Criteria:
1. Target diagnosis (Acute Bronchitis) status is NO LONGER 'Active'.
   - Accepted: 'Resolved', 'Inactive', 'Completed', OR has an endDate/dateResolved.
2. No new diagnosis records created (Anti-gaming).
   - The user should edit the existing record, not create a duplicate 'Resolved' one.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_patient_diagnosis(traj, env_info, task_info):
    """
    Verify that the diagnosis was resolved correctly.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    target_doc = result.get('target_diagnosis_doc', {})
    all_diagnoses = result.get('all_diagnoses', [])
    initial_count = int(result.get('initial_count', 1))
    
    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Verify the specific seeded document was updated ---
    # We look at the doc with the ID we seeded.
    doc_data = target_doc.get('data', target_doc)
    status = str(doc_data.get('status', '')).strip().lower()
    date_resolved = doc_data.get('dateResolved') or doc_data.get('endDate')
    
    is_resolved_status = status in ['resolved', 'inactive', 'completed', 'recovered']
    has_end_date = date_resolved is not None and str(date_resolved).strip() != ""
    
    # Check if the seeded doc itself was modified to be resolved
    seeded_doc_resolved = is_resolved_status or has_end_date
    seeded_doc_still_active = (status == 'active') and not has_end_date
    
    if seeded_doc_resolved:
        score += 70
        feedback_parts.append("Target diagnosis successfully marked as resolved/inactive.")
    elif seeded_doc_still_active:
        feedback_parts.append("Target diagnosis is still 'Active'.")
    else:
        # Edge case: status is empty or something else
        feedback_parts.append(f"Target diagnosis status is '{status}' (unclear if resolved).")

    # --- Criterion 2: Check for Duplicate/New Records (Anti-Gaming) ---
    current_count = len(all_diagnoses)
    
    # Perfect case: Count didn't change (1 -> 1), implying edit.
    if current_count == initial_count:
        if seeded_doc_resolved:
            score += 30
            feedback_parts.append("Correctly edited the existing record (no duplicates created).")
        else:
            # If they didn't resolve it, they get 0 points anyway, but no extra penalty here
            pass
            
    elif current_count > initial_count:
        # Agent created a NEW diagnosis instead of editing.
        # Check if ANY of the new docs are "Bronchitis" and "Resolved"
        new_resolved_found = False
        for doc in all_diagnoses:
            d = doc.get('data', doc)
            d_name = d.get('diagnosis', '').lower()
            d_status = str(d.get('status', '')).lower()
            
            # If it's bronchitis and resolved, they did the clinical task but wrong workflow
            if "bronchitis" in d_name and (d_status in ['resolved', 'inactive'] or d.get('endDate')):
                new_resolved_found = True
                
        if new_resolved_found:
            # They achieved the clinical goal but cluttered the record
            # If they ALREADY got points for editing the original (unlikely if count increased), cap it.
            # If they didn't edit the original (so seeded_doc_resolved is False):
            if not seeded_doc_resolved:
                score += 40 # Partial credit for creating a new resolved record
                feedback_parts.append("Partial Credit: Created a NEW resolved diagnosis record instead of editing the existing one. This clutters the patient history.")
            else:
                 feedback_parts.append("Warning: You edited the original BUT also created a duplicate.")
        else:
            feedback_parts.append("Created new diagnosis records but none were the resolved bronchitis.")
            
    elif current_count < initial_count:
        # Agent DELETED the diagnosis?
        # This removes it from active list, but destroys history. Bad practice.
        score += 10
        feedback_parts.append("Warning: Diagnosis record was deleted. Standard practice is to mark as resolved, not delete.")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }