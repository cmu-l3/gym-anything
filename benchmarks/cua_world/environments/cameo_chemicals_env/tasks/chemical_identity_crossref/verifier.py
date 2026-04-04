#!/usr/bin/env python3
"""
Verifier for chemical_identity_crossref task.

Checks that the agent created a text file containing the correct CAS numbers,
formulas, and molecular weights for 5 specific chemicals.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_identity_crossref(traj, env_info, task_info):
    """
    Verify the chemical identity report content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', [])
    mw_tolerance = metadata.get('mw_tolerance', 1.5)
    
    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file criteria
    if not result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at ~/Documents/chemical_identity_report.txt"}

    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file was not modified during the task session (anti-gaming check failed)"}

    # Load report content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(result['output_path'], temp_report.name)
        with open(temp_report.name, 'r', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read report file: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    score = 0
    feedback_parts = []
    
    # Base score for creating the file
    score += 10
    feedback_parts.append("Report file created")

    # Content Verification
    # We look for the presence of key data points anywhere in the file (robust to formatting)
    
    chemicals_found = 0
    cas_found = 0
    formula_found = 0
    mw_found = 0
    
    content_lower = content.lower()
    
    for chem in expected_chemicals:
        chem_name = chem['name']
        chem_cas = chem['cas']
        chem_formulas = [f.lower() for f in chem['formula']]
        chem_mw = chem['mw']
        
        chem_feedback = []
        
        # 1. Check Name Presence (Loose check)
        if chem_name.lower() in content_lower:
            chemicals_found += 1
        
        # 2. Check CAS (Strict check)
        # CAS numbers are very specific strings
        if chem_cas in content:
            cas_found += 1
            score += 10  # High value for correct CAS
            chem_feedback.append("CAS OK")
        else:
            chem_feedback.append(f"Missing CAS {chem_cas}")
            
        # 3. Check Formula
        # Look for any valid representation
        f_ok = False
        for f in chem_formulas:
            if f in content_lower:
                f_ok = True
                break
        
        # Fallback regex for formulas (e.g. C3H4O might be written C3-H4-O or similar)
        if not f_ok:
            # Simple spacing check
            for f in chem_formulas:
                spaced = " ".join(list(f)) # C 3 H 4 O
                if spaced in content_lower:
                    f_ok = True
                    break
                    
        if f_ok:
            formula_found += 1
            score += 4
            chem_feedback.append("Formula OK")
        else:
            chem_feedback.append("Missing Formula")

        # 4. Check Molecular Weight
        # Look for the number with some tolerance
        # Regex to find floating point numbers
        numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
        mw_ok = False
        for num_str in numbers:
            try:
                val = float(num_str)
                if abs(val - chem_mw) <= mw_tolerance:
                    mw_ok = True
                    break
            except ValueError:
                continue
        
        if mw_ok:
            mw_found += 1
            score += 4
            chem_feedback.append("MW OK")
        else:
            chem_feedback.append(f"Missing MW ~{chem_mw}")

    feedback_parts.append(f"Found {cas_found}/5 CAS numbers")
    
    # Pass logic
    # Need at least 3 correct CAS numbers and a total score >= 70
    passed = (cas_found >= 3) and (score >= 70)
    
    if passed:
        feedback_parts.append("PASSED")
    else:
        feedback_parts.append("FAILED")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "chemicals_found": chemicals_found,
            "cas_found": cas_found,
            "formula_found": formula_found,
            "mw_found": mw_found
        }
    }