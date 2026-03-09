#!/usr/bin/env python3
"""
Verifier for generate_business_key_equality task.

Criteria:
1. Product.java exists and compiles (20 pts)
2. hashCode() and equals() methods exist (20 pts)
3. Usage of java.util.Objects.hash (Correct Style) (20 pts)
4. Inclusion of 'sku' field (20 pts)
5. Exclusion of all other fields (id, name, price, stockQuantity) (20 pts)

Anti-gaming:
- File must be modified during task.
- Code must actually compile.
"""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_business_key_equality(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    result_json_path = "/tmp/task_result.json"
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Extract Data
    file_content = result.get('file_content', '')
    compile_success = result.get('compile_success', False)
    file_modified = result.get('file_modified', False)
    
    score = 0
    feedback = []

    # Criterion 1: File Check & Modification (Anti-gaming)
    if not file_content:
        return {"passed": False, "score": 0, "feedback": "Product.java is empty or missing"}
    
    if not file_modified:
        feedback.append("WARNING: File was not modified during the task.")
        # We don't fail immediately but this is suspicious for a generation task
    
    if compile_success:
        score += 20
        feedback.append("Code compiles successfully")
    else:
        feedback.append("Code failed to compile")

    # Criterion 2: Methods Exist
    # Regex to find methods. Note: Agent might rearrange code.
    has_hash = re.search(r'public\s+int\s+hashCode\s*\(\s*\)', file_content)
    has_equals = re.search(r'public\s+boolean\s+equals\s*\(\s*Object', file_content)
    
    if has_hash and has_equals:
        score += 20
        feedback.append("Both hashCode and equals methods found")
    else:
        feedback.append("Missing hashCode or equals method")
        # Early exit if methods don't exist, as we can't check logic
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # Extract method bodies for logic analysis
    # This is a simple extractor that counts braces.
    def get_method_body(content, method_sig_regex):
        match = re.search(method_sig_regex, content)
        if not match:
            return ""
        start_idx = match.end()
        # Find opening brace
        open_brace_idx = content.find('{', start_idx)
        if open_brace_idx == -1: 
            return ""
        
        balance = 1
        curr = open_brace_idx + 1
        while curr < len(content) and balance > 0:
            if content[curr] == '{':
                balance += 1
            elif content[curr] == '}':
                balance -= 1
            curr += 1
        return content[open_brace_idx:curr]

    hash_body = get_method_body(file_content, r'public\s+int\s+hashCode\s*\(\s*\)')
    equals_body = get_method_body(file_content, r'public\s+boolean\s+equals\s*\(\s*Object\s+\w+\s*\)')

    # Criterion 3: Style (Objects.hash)
    # Expected: return Objects.hash(sku);
    if 'Objects.hash' in hash_body:
        score += 20
        feedback.append("Correct style: used java.util.Objects.hash")
    elif 'prime * result' in hash_body:
        feedback.append("Wrong style: used legacy arithmetic hash calculation")
    else:
        feedback.append("Wrong style: Objects.hash not found")

    # Criterion 4: Inclusion of SKU
    if 'sku' in hash_body and 'sku' in equals_body:
        score += 20
        feedback.append("Business Key (sku) included in logic")
    else:
        feedback.append("Business Key (sku) MISSING from equality logic")

    # Criterion 5: Exclusion of Forbidden Fields
    forbidden_fields = ['id', 'name', 'price', 'stockQuantity']
    found_forbidden = []
    
    for field in forbidden_fields:
        # Check if field is referenced in the bodies
        # We search for field name surrounded by non-word chars to avoid matching substrings
        pattern = re.compile(r'\b' + re.escape(field) + r'\b')
        if pattern.search(hash_body) or pattern.search(equals_body):
            found_forbidden.append(field)
    
    if not found_forbidden:
        score += 20
        feedback.append("Correctly excluded mutable/surrogate fields")
    else:
        feedback.append(f"Failed: Logic includes forbidden fields: {', '.join(found_forbidden)}")

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": "; ".join(feedback)
    }