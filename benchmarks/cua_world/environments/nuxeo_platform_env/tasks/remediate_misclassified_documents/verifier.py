#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime

def parse_nuxeo_date(date_str):
    """Parse Nuxeo ISO 8601 date string to timestamp."""
    if not date_str:
        return 0.0
    # Nuxeo format example: 2023-10-27T10:00:00.00Z
    try:
        # Remove 'Z' if present for standard parsing
        if date_str.endswith('Z'):
            date_str = date_str[:-1]
        dt = datetime.fromisoformat(date_str)
        return dt.timestamp()
    except ValueError:
        return 0.0

def verify_remediate_misclassified_documents(traj, env_info, task_info):
    """
    Verify that the agent correctly updated the metadata of misclassified documents
    while preserving the correctly classified one.
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

    # Extract Data
    docs = result.get("documents", {})
    task_start_ts = result.get("task_start_ts", 0)
    control_initial_mod_str = result.get("control_initial_mod", "")
    control_initial_ts = parse_nuxeo_date(control_initial_mod_str)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Fix 'Vendor-Contract-Alpha' (30 pts)
    # ---------------------------------------------------------
    doc1 = docs.get("Vendor-Contract-Alpha", {})
    nature1 = doc1.get("nature", "").lower()
    mod1_str = doc1.get("modified", "")
    mod1_ts = parse_nuxeo_date(mod1_str)

    if nature1 == "contract":
        score += 20
        feedback_parts.append("Vendor Contract nature corrected.")
        # Check if actually modified during task
        if mod1_ts > task_start_ts:
            score += 10
            feedback_parts.append("(Verified modified during task)")
        else:
            feedback_parts.append("(Warning: Modification timestamp suspicious)")
    else:
        feedback_parts.append(f"Vendor Contract nature is '{nature1}' (expected 'contract').")

    # ---------------------------------------------------------
    # Criterion 2: Fix 'Service-Level-Agreement-2023' (30 pts)
    # ---------------------------------------------------------
    doc2 = docs.get("Service-Level-Agreement-2023", {})
    nature2 = doc2.get("nature", "").lower()
    mod2_str = doc2.get("modified", "")
    mod2_ts = parse_nuxeo_date(mod2_str)

    if nature2 == "contract":
        score += 20
        feedback_parts.append("SLA nature corrected.")
        if mod2_ts > task_start_ts:
            score += 10
            feedback_parts.append("(Verified modified during task)")
        else:
            feedback_parts.append("(Warning: Modification timestamp suspicious)")
    else:
        feedback_parts.append(f"SLA nature is '{nature2}' (expected 'contract').")

    # ---------------------------------------------------------
    # Criterion 3: Preserve 'Office-Supplies-Invoice-9921' (30 pts)
    # ---------------------------------------------------------
    doc3 = docs.get("Office-Supplies-Invoice-9921", {})
    nature3 = doc3.get("nature", "").lower()
    mod3_str = doc3.get("modified", "")
    mod3_ts = parse_nuxeo_date(mod3_str)

    if nature3 == "invoice":
        score += 15
        feedback_parts.append("Control invoice nature preserved.")
        
        # Anti-gaming: Check if it was unnecessarily modified
        # Allow a small buffer (e.g. 1 sec) or strictly check if timestamp changed significantly
        # If timestamp is identical to initial, full points.
        # If changed but still 'invoice', partial points (maybe accidental edit/save without change).
        
        # In Nuxeo, saving a doc even with no changes often updates dc:modified.
        # Ideally, this doc should not be touched.
        if mod3_str == control_initial_mod_str:
            score += 15
            feedback_parts.append("(Control document correctly untouched)")
        else:
            # If modified but value correct, penalize slightly (agent might have bulk edited folder)
            score += 5 
            feedback_parts.append("(Warning: Control document was modified, though value is correct)")
    else:
        feedback_parts.append(f"Control invoice nature changed to '{nature3}' (FAIL).")

    # ---------------------------------------------------------
    # Criterion 4: Data Integrity (10 pts)
    # ---------------------------------------------------------
    if doc1.get("uid") and doc2.get("uid") and doc3.get("uid"):
        score += 10
    else:
        feedback_parts.append("One or more documents missing/deleted.")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }