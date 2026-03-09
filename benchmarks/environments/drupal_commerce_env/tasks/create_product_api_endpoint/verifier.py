#!/usr/bin/env python3
"""
Verifier for Create Product API Endpoint task.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_product_api_endpoint(traj, env_info, task_info):
    """
    Verify the product API endpoint creation.
    
    Checks:
    1. HTTP 200 OK on /api/v1/products (20 pts)
    2. Response is valid JSON (15 pts)
    3. REST & Serialization modules enabled (10 pts)
    4. Response contains list of products (15 pts)
    5. Required fields (ID, Title, SKU, Price) are present in data (20 pts)
    6. Content-Type header is application/json (10 pts)
    7. Public access (Anonymous) confirmed (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result file: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Modules (10 pts)
    if result.get('modules_enabled', False):
        score += 10
        feedback_parts.append("REST/Serialization modules enabled")
    else:
        feedback_parts.append("Modules NOT enabled")

    # 2. HTTP Status (20 pts) + Public Access (10 pts)
    # The export script curls without auth, so 200 implies public access
    http_status = str(result.get('http_status', '0'))
    if http_status == '200':
        score += 30 # 20 for working, 10 for public access
        feedback_parts.append("Endpoint returns HTTP 200 (Public Access OK)")
    elif http_status == '403':
        feedback_parts.append("Endpoint returns HTTP 403 (Access Forbidden - Permission issue)")
    elif http_status == '404':
        feedback_parts.append("Endpoint returns HTTP 404 (Path incorrect or View not saved)")
    else:
        feedback_parts.append(f"Endpoint returns HTTP {http_status}")

    # 3. JSON Validity (15 pts) & Content Type (10 pts)
    is_valid_json = result.get('is_valid_json', False)
    content_type = result.get('content_type', '')
    
    if is_valid_json:
        score += 15
        feedback_parts.append("Valid JSON response")
    else:
        feedback_parts.append("Invalid JSON response")

    if 'application/json' in content_type:
        score += 10
        feedback_parts.append("Correct Content-Type")
    else:
        feedback_parts.append(f"Incorrect Content-Type: {content_type}")

    # 4. Data Content Analysis (15 pts + 20 pts)
    api_data_str = result.get('api_response_sample', '[]')
    
    # Analyze the JSON structure
    data_score = 0
    field_score = 0
    
    try:
        data = json.loads(api_data_str)
        
        # Check if it's a list and has items (15 pts)
        if isinstance(data, list) and len(data) > 0:
            data_score += 15
            feedback_parts.append(f"Response contains {len(data)} items")
            
            # Check fields in the first item (20 pts)
            first_item = data[0]
            fields_found = []
            
            # Helper to find keys case-insensitively or nested
            def find_key(item, target):
                # Direct check
                if target in item: return True
                # Case insensitive check
                for k in item.keys():
                    if k.lower() == target.lower(): return True
                    # Check for field_ prefix (common in Drupal)
                    if k.lower() == f"field_{target}".lower(): return True
                return False

            # Check Title
            if find_key(first_item, 'title'): fields_found.append('title')
            
            # Check ID (product_id, nid, uuid)
            if find_key(first_item, 'product_id') or find_key(first_item, 'uuid'): fields_found.append('id')
            
            # Check SKU (often requires relationship)
            if find_key(first_item, 'sku') or find_key(first_item, 'sku_1'): fields_found.append('sku')
            
            # Check Price (often requires relationship, might be price, price__number, etc)
            # Price often comes as a formatted string or number field
            has_price = False
            for k in first_item.keys():
                if 'price' in k.lower(): has_price = True
            if has_price: fields_found.append('price')
            
            if len(fields_found) >= 4:
                field_score += 20
                feedback_parts.append("All required fields found (ID, Title, SKU, Price)")
            elif len(fields_found) > 0:
                partial = int(20 * (len(fields_found) / 4))
                field_score += partial
                feedback_parts.append(f"Some fields found: {', '.join(fields_found)}")
            else:
                feedback_parts.append("No required fields found in JSON object")
                
        else:
            feedback_parts.append("Response is not a list or is empty")
            
    except json.JSONDecodeError:
        pass # Already handled by is_valid_json check

    score += data_score
    score += field_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }