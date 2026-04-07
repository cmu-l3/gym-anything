#!/usr/bin/env python3
"""
Verifier for W-9 Form Completion task.

Checks:
1. File existence and creation time (Anti-gaming).
2. Browser history (Source legitimacy).
3. Form field content (Correctness).
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize text for comparison (trim, lower, remove extra spaces)."""
    if not text:
        return ""
    # Remove PDF typical artifacts like leading/trailing slashes if raw parsing occurred
    text = str(text).strip()
    if text.startswith('/'):
        text = text[1:]
    return " ".join(text.lower().split())

def verify_w9_form_completion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {})
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/w9_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Timestamp (20 pts)
    if result.get("file_exists"):
        if result.get("file_created_during_task"):
            score += 20
            feedback.append("PDF file created successfully during task.")
        else:
            score += 5
            feedback.append("PDF file exists but timestamp suggests it wasn't modified during this session.")
    else:
        feedback.append("Target PDF file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: IRS Source Verification (10 pts)
    if result.get("irs_visited"):
        score += 10
        feedback.append("Confirmed visit to IRS website.")
    else:
        feedback.append("No history of visiting irs.gov found.")

    # Criterion 3: Field Content Verification (70 pts)
    # The keys in the W-9 form can be cryptic (e.g., 'topmostSubform[0]...').
    # We search for the expected values in the *values* of the extracted dictionary.
    
    fields = result.get("field_data", {})
    if not fields:
        feedback.append("Could not extract form data (empty or parsing failed).")
        # Fallback check: If parsing failed but file size changed significantly, giving small partial credit?
        # No, we need accuracy.
    else:
        # Flatten values for easier searching
        all_values = [normalize_text(v) for v in fields.values()]
        
        # Check Name (15 pts)
        name_target = normalize_text(expected.get("name", "Acme Industrial Supply LLC"))
        if any(name_target in v for v in all_values):
            score += 15
            feedback.append("Name matched.")
        else:
            feedback.append(f"Name '{expected.get('name')}' not found in form.")

        # Check Business Name (10 pts)
        biz_target = normalize_text(expected.get("business_name", "Acme Supply"))
        if any(biz_target in v for v in all_values):
            score += 10
            feedback.append("Business Name matched.")
        else:
            feedback.append("Business Name not found.")

        # Check Address (10 pts)
        addr_target = normalize_text(expected.get("address", "4500 Auto Mall Dr"))
        if any(addr_target in v for v in all_values):
            score += 10
            feedback.append("Address matched.")
        else:
            feedback.append("Address not found.")

        # Check City/State/Zip (10 pts)
        # Often split or combined, try partial match
        city_target = normalize_text("Kersey")
        zip_target = "15846"
        if any(city_target in v for v in all_values) and any(zip_target in v for v in all_values):
            score += 10
            feedback.append("City/State/Zip matched.")
        else:
            feedback.append("City/State/Zip mismatch.")

        # Check EIN (15 pts)
        # EIN might be formatted with or without dash
        ein_raw = expected.get("ein", "12-3456789")
        ein_clean = ein_raw.replace("-", "")
        
        ein_found = False
        for v in all_values:
            v_clean = v.replace("-", "").replace(" ", "")
            if ein_clean in v_clean:
                ein_found = True
                break
        
        if ein_found:
            score += 15
            feedback.append("EIN matched.")
        else:
            feedback.append("EIN not found.")

        # Check Checkbox (10 pts)
        # C Corp checkbox usually has value 'Yes', 'On', or '1'. We look for the C Corp key specifically?
        # Since we flattened values, hard to map key. But standard W-9 often names fields like 'Classification'.
        # Heuristic: Check if we find a 'Yes' or 'On' associated with a key containing 'C Corp' or similar.
        # However, we only have values in the flat list strategy above. 
        # Let's iterate items for a better check.
        c_corp_checked = False
        for k, v in fields.items():
            k_lower = k.lower()
            v_lower = str(v).lower()
            # Look for keys like "C Corporation" or "Classification" with value "C Corporation" or "Yes"
            if ("c corp" in k_lower or "classification" in k_lower) and \
               (v_lower in ["yes", "on", "true", "c corporation", "1"]):
                c_corp_checked = True
                break
            # Some forms use radio buttons where the value IS the label
            if "c corporation" in v_lower:
                c_corp_checked = True
                break
        
        if c_corp_checked:
            score += 10
            feedback.append("Tax Classification checked.")
        else:
            # Flexible: if we can't confirm, we don't penalize too hard if text fields are perfect
            feedback.append("Could not verify Tax Classification checkbox (key naming varies).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }