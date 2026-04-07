#!/usr/bin/env python3
"""
Verifier for bg_check_compliance_config task.

Evaluates if the agent successfully added 5 background screening types 
and 3 background check agencies with accurate contact details.

Scoring (100 points total, Pass Threshold = 60):
- 5 Types x 10 pts = 50 pts
- 3 Agencies active x 8 pts = 24 pts
- 3 Agencies contact details correct = 26 pts (9 + 8 + 9)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_TYPES = [
    "Drug & Substance Screening",
    "Criminal Background Check",
    "Education & Credential Verification",
    "Professional License Verification",
    "Safety Certification Compliance"
]

EXPECTED_AGENCIES = [
    {
        "name": "NationalScreen Inc.",
        "keywords": ["nationalscreen"],
        "phone": "555-0147",
        "website": "nationalscreen",
        "pts_active": 8,
        "pts_details": 9
    },
    {
        "name": "VerifyFirst Solutions",
        "keywords": ["verifyfirst"],
        "phone": "555-0233",
        "website": "verifyfirst",
        "pts_active": 8,
        "pts_details": 8
    },
    {
        "name": "SafeHire Compliance Group",
        "keywords": ["safehire"],
        "phone": "555-0391",
        "website": "safehire",
        "pts_active": 8,
        "pts_details": 9
    }
]

PASS_THRESHOLD = 60

def row_has_substring(row_dict, substring):
    """Checks if any value in the database row contains the given substring (case-insensitive)."""
    substring_lower = substring.lower()
    for val in row_dict.values():
        if val and isinstance(val, str) and substring_lower in val.lower():
            return True
    return False

def verify_bg_check_compliance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON export
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/bg_check_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    types_rows = result_data.get('types', [])
    agencies_rows = result_data.get('agencies', [])
    
    score = 0
    feedback = []

    # 1. Verify Screening Types
    for expected_type in EXPECTED_TYPES:
        found = False
        is_active = False
        
        for row in types_rows:
            if row_has_substring(row, expected_type):
                found = True
                if str(row.get('isactive', '1')) == '1':
                    is_active = True
                break
                
        if found and is_active:
            score += 10
            feedback.append(f"Type '{expected_type}' found and active (10/10)")
        elif found:
            score += 5
            feedback.append(f"Type '{expected_type}' found but inactive (5/10)")
        else:
            feedback.append(f"Type '{expected_type}' missing (0/10)")

    # 2. Verify Vendor Agencies
    for exp_agency in EXPECTED_AGENCIES:
        found = False
        is_active = False
        phone_match = False
        website_match = False
        
        for row in agencies_rows:
            # Check if agency name keyword is present in this row
            if any(row_has_substring(row, kw) for kw in exp_agency['keywords']):
                found = True
                if str(row.get('isactive', '1')) == '1':
                    is_active = True
                
                # Verify details
                if row_has_substring(row, exp_agency['phone']):
                    phone_match = True
                if row_has_substring(row, exp_agency['website']):
                    website_match = True
                break
                
        # Scoring Agency Existence
        if found and is_active:
            score += exp_agency['pts_active']
            feedback.append(f"Agency '{exp_agency['name']}' found and active ({exp_agency['pts_active']}/{exp_agency['pts_active']})")
        elif found:
            score += exp_agency['pts_active'] // 2
            feedback.append(f"Agency '{exp_agency['name']}' found but inactive ({exp_agency['pts_active'] // 2}/{exp_agency['pts_active']})")
        else:
            feedback.append(f"Agency '{exp_agency['name']}' missing (0/{exp_agency['pts_active']})")

        # Scoring Agency Details
        if found:
            details_max = exp_agency['pts_details']
            if phone_match and website_match:
                score += details_max
                feedback.append(f"  └─ Details (Phone & Web) correct ({details_max}/{details_max})")
            elif phone_match or website_match:
                partial_pts = details_max // 2
                score += partial_pts
                feedback.append(f"  └─ Details partially correct ({partial_pts}/{details_max})")
            else:
                feedback.append(f"  └─ Details incorrect/missing (0/{details_max})")

    # Anti-gaming check: If the types length hasn't changed since start AND we scored 0 on types, note it
    initial_types = result_data.get('initial_types_count', 0)
    current_types = len(types_rows)
    if current_types <= initial_types and score == 0:
        feedback.append("No new entries detected.")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }