#!/usr/bin/env python3
"""
Verifier for REST API Testing with HTTP Files task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_http_file(traj, env_info, task_info):
    """
    Verify that api-tests.http file was created correctly.
    
    Checks:
    1. File exists at correct location
    2. Variable definition (@baseUrl or similar)
    3. GET /api/users request
    4. POST /api/users request with JSON body (name and email fields)
    5. Content-Type header present
    6. Request separators (###) used
    7. GET /api/users/{id} request (specific user)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/workspace/api_test/api-tests.http"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.http')
    
    try:
        # Try to copy the file
        try:
            copy_from_env(container_path, temp_file.name)
        except Exception as e:
            logger.error(f"Failed to copy HTTP file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ File not found: api-tests.http not created at {container_path}"
            }
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File api-tests.http is empty or not found"
            }
        
        # Read file content
        content = read_file_content(temp_file.name)
        
        if not content or len(content.strip()) < 10:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File api-tests.http is empty or too short"
            }
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Normalize content for easier checking
        content_lower = content.lower()
        
        # Criterion 1: File exists (already verified above)
        criteria_passed += 1
        feedback_parts.append("✅ File api-tests.http exists")
        
        # Criterion 2: Variable definition (@baseUrl or similar)
        variable_patterns = [
            r'@baseurl\s*=',
            r'@base_url\s*=',
            r'@url\s*=',
            r'@host\s*='
        ]
        has_variable = False
        for pattern in variable_patterns:
            if re.search(pattern, content_lower):
                has_variable = True
                break
        
        if has_variable:
            criteria_passed += 1
            feedback_parts.append("✅ Variable definition found")
        else:
            feedback_parts.append("❌ Variable definition not found (expected @baseUrl = ...)")
        
        # Criterion 3: GET /api/users request
        get_users_pattern = r'GET\s+.*?/api/users(?:\s|$)'
        if re.search(get_users_pattern, content, re.IGNORECASE):
            criteria_passed += 1
            feedback_parts.append("✅ GET /api/users request found")
        else:
            feedback_parts.append("❌ GET /api/users request not found")
        
        # Criterion 4: POST /api/users with JSON body containing "name" and "email"
        post_pattern = r'POST\s+.*?/api/users'
        has_post = re.search(post_pattern, content, re.IGNORECASE)
        
        if has_post:
            # Check if JSON body with name and email exists after POST
            post_index = has_post.start()
            content_after_post = content[post_index:post_index+500]  # Look at next 500 chars
            
            has_name = '"name"' in content_after_post or "'name'" in content_after_post
            has_email = '"email"' in content_after_post or "'email'" in content_after_post
            has_json_braces = '{' in content_after_post and '}' in content_after_post
            
            if has_name and has_email and has_json_braces:
                criteria_passed += 1
                feedback_parts.append("✅ POST /api/users with JSON body (name, email) found")
            else:
                feedback_parts.append("❌ POST request found but JSON body incomplete (missing name/email fields)")
        else:
            feedback_parts.append("❌ POST /api/users request not found")
        
        # Criterion 5: Content-Type header
        content_type_patterns = [
            r'content-type\s*:\s*application/json',
            r'content-type:\s*application/json'
        ]
        has_content_type = False
        for pattern in content_type_patterns:
            if re.search(pattern, content_lower):
                has_content_type = True
                break
        
        if has_content_type:
            criteria_passed += 1
            feedback_parts.append("✅ Content-Type header found")
        else:
            feedback_parts.append("❌ Content-Type header not found")
        
        # Criterion 6: Request separators (###)
        if '###' in content:
            separator_count = content.count('###')
            criteria_passed += 1
            feedback_parts.append(f"✅ Request separators found ({separator_count} separators)")
        else:
            feedback_parts.append("❌ Request separators (###) not found")
        
        # Criterion 7: GET /api/users/{id} (specific user)
        specific_user_pattern = r'GET\s+.*?/api/users/\d+'
        if re.search(specific_user_pattern, content, re.IGNORECASE):
            criteria_passed += 1
            feedback_parts.append("✅ GET /api/users/{id} request found")
        else:
            # Be more lenient - check for any users/{something}
            lenient_pattern = r'GET\s+.*?/api/users/\w+'
            if re.search(lenient_pattern, content, re.IGNORECASE):
                criteria_passed += 1
                feedback_parts.append("✅ GET /api/users/{id} request found")
            else:
                feedback_parts.append("❌ GET /api/users/{id} request not found")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": f"{feedback} | Score: {criteria_passed}/{total_criteria} criteria met"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
