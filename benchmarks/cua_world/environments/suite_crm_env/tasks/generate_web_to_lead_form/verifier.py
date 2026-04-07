#!/usr/bin/env python3
"""
Verifier for generate_web_to_lead_form task.

VERIFICATION METRICS:
1. File Existence & Freshness: Verifies the file is saved locally and created during the task.
2. Authentic CRM Code: Parses HTML to ensure it contains SuiteCRM's proprietary 'WebToLeadCapture' endpoint,
   preventing agents from hallucinating a generic form.
3. Redirect URL Configuration: Confirms the requested redirect URL is present in the form action/hidden fields.
4. Lead Fields: Verifies inputs for requested fields (First Name, Last Name, Email) are present.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_web_to_lead_form(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_file_path = metadata.get('expected_file_path', '/home/ga/Documents/tradeshow_lead_form.html')
    redirect_url = metadata.get('expected_redirect_url', 'https://www.meridian-tech.com/digital-catalog')
    auth_string = metadata.get('anti_hallucination_string', 'WebToLeadCapture')
    expected_fields = metadata.get('expected_fields', ['first_name', 'last_name', 'email1'])

    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
    
    score = 0
    feedback_parts = []
    html_content = ""

    try:
        # 1. Read exported metadata
        copy_from_env("/tmp/generate_web_to_lead_form_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        file_exists = result.get('file_exists', False)
        created_during_task = result.get('file_created_during_task', False)
        file_size = result.get('file_size_bytes', 0)

        # Early exit if file isn't there
        if not file_exists:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Target file {expected_file_path} does not exist. Agent failed to save the output."
            }

        # CRITERION 1: File Existence & Freshness (20 points)
        if created_during_task and file_size > 200:
            score += 20
            feedback_parts.append("File exists and was legitimately created during task")
        elif file_exists:
            # File exists but was likely an old file or empty
            score += 5
            feedback_parts.append(f"File exists but freshness check failed or size too small ({file_size} bytes)")
            
        # 2. Extract HTML file contents
        copy_from_env(expected_file_path, temp_html.name)
        with open(temp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
            html_content = f.read()
            
        # CRITERION 2: Authentic SuiteCRM Code (Anti-Hallucination) (30 points)
        # It must contain the specific SuiteCRM entryPoint.
        if auth_string.lower() in html_content.lower():
            score += 30
            feedback_parts.append(f"Authentic SuiteCRM HTML detected ({auth_string})")
        else:
            feedback_parts.append("FAIL: HTML does not look like authentic SuiteCRM generated code")
            
        # CRITERION 3: Correct Redirect URL Configuration (30 points)
        if redirect_url in html_content:
            score += 30
            feedback_parts.append("Correct redirect URL found in HTML")
        else:
            feedback_parts.append("FAIL: Redirect URL is missing or incorrect in generated form")
            
        # CRITERION 4: Required Fields Present (20 points)
        fields_found = [f for f in expected_fields if f.lower() in html_content.lower()]
        if len(fields_found) == len(expected_fields):
            score += 20
            feedback_parts.append("All requested fields found in HTML")
        else:
            points = int((len(fields_found) / len(expected_fields)) * 20)
            score += points
            feedback_parts.append(f"Found {len(fields_found)}/{len(expected_fields)} requested fields")

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification encountered an error: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_html.name):
            os.unlink(temp_html.name)
            
    # Key criteria MUST be met to pass
    has_authentic_code = auth_string.lower() in html_content.lower()
    has_redirect = redirect_url in html_content
    passed = score >= 80 and has_authentic_code and has_redirect
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }