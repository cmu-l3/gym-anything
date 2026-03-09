#!/usr/bin/env python3
"""Verifier for create_getfeatureinfo_template task."""

import json
import tempfile
import os
import base64
import re

def verify_create_getfeatureinfo_template(traj, env_info, task_info):
    """
    Verify that a custom Freemarker template was created and produces 
    the correct HTML output for WMS GetFeatureInfo.
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_attributes = metadata.get('required_attributes', ["name", "iso_a3", "pop_est", "economy", "continent"])

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_getfeatureinfo_template_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Location (15 points)
    if result.get('file_exists'):
        score += 15
        feedback_parts.append("Template file 'content.ftl' found in correct directory")
    else:
        return {"passed": False, "score": 0, "feedback": "Template file 'content.ftl' NOT found in the expected GeoServer data directory"}

    # 2. File Content Analysis (50 points total)
    file_content = ""
    try:
        if result.get('file_content_base64'):
            file_content = base64.b64decode(result.get('file_content_base64')).decode('utf-8', errors='ignore')
    except Exception:
        feedback_parts.append("Error decoding file content")

    if file_content:
        # Check Freemarker syntax (10 points)
        if '<#list' in file_content and ('${' in file_content or '$' in file_content):
            score += 10
            feedback_parts.append("Valid Freemarker syntax detected")
        else:
            feedback_parts.append("Warning: Freemarker syntax (loops/variables) not clearly detected")

        # Check Required Attributes (40 points - 8 per attribute)
        # We look for the attribute name in the file content (e.g. feature.name.value or similar)
        # We are lenient: if the attribute name appears in the file, we assume they tried to use it.
        found_attrs = 0
        for attr in required_attributes:
            if attr in file_content:
                score += 8
                found_attrs += 1
            else:
                feedback_parts.append(f"Missing attribute reference: {attr}")
        
        if found_attrs == len(required_attributes):
            feedback_parts.append(f"All {len(required_attributes)} required attributes referenced in template")
        else:
            feedback_parts.append(f"Referenced {found_attrs}/{len(required_attributes)} attributes")
            
    # 3. Functional Verification (Live Response) (25 points)
    live_response = ""
    try:
        if result.get('live_response_base64'):
            live_response = base64.b64decode(result.get('live_response_base64')).decode('utf-8', errors='ignore')
    except Exception:
        pass

    if result.get('response_changed') and live_response:
        # Basic check: is it HTML?
        if "html" in live_response.lower() or "<div" in live_response or "<table" in live_response:
            score += 10
            feedback_parts.append("GetFeatureInfo returns custom HTML")
            
            # Data check: Does it contain data for France? (Lat 47, Lon 2)
            # We look for typical data values that should be in the response if it worked
            data_found = 0
            # Common values for France in Natural Earth: "France", "FRA", "Europe"
            if "France" in live_response:
                data_found += 5
            if "FRA" in live_response:
                data_found += 5
            if "Europe" in live_response:
                data_found += 5
                
            if data_found > 0:
                score += data_found
                feedback_parts.append("Live response contains correct feature data")
            else:
                feedback_parts.append("Live response does not seem to contain expected data values (France, FRA, Europe)")
        else:
            feedback_parts.append("Live response does not appear to be formatted HTML")
    else:
        feedback_parts.append("GetFeatureInfo response is identical to default (template not active or not working)")

    # 4. Anti-Gaming (10 points)
    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File timestamp indicates it was not created during this task session")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }