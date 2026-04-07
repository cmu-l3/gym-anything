#!/usr/bin/env python3
"""
Verifier for configure_trusted_hosts task.

Verification Strategy:
1. Parse the PHP INI config file content.
2. Verify 'analytics.internal.corp' is in trusted_hosts.
3. Verify 'localhost' and '127.0.0.1' are PRESERVED.
4. Verify file integrity (valid PHP/INI syntax).
5. Verify file was modified during task.

Scoring:
- File Integrity (Valid PHP/INI): 20 pts
- New Host Added: 40 pts
- Localhost Preserved: 20 pts
- 127.0.0.1 Preserved: 20 pts
"""

import json
import logging
import os
import tempfile
import base64
import re
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_php_ini_array(content: str, key: str) -> list:
    """
    Rudimentary parser for PHP INI array syntax like trusted_hosts[] = "value"
    """
    values = []
    # Regex to find lines like: trusted_hosts[] = "value" or trusted_hosts[] = value
    # Case insensitive for key
    pattern = re.compile(rf'^\s*{re.escape(key)}\s*\[\]\s*=\s*["\']?([^"\';\r\n]+)["\']?', re.MULTILINE | re.IGNORECASE)
    
    for match in pattern.finditer(content):
        val = match.group(1).strip()
        values.append(val)
    
    return values

def verify_configure_trusted_hosts(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_host = metadata.get('expected_host', 'analytics.internal.corp')
    required_hosts = metadata.get('required_hosts', ['localhost', '127.0.0.1'])

    try:
        # Load result
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        
        # 1. File Integrity & Existence
        if not result.get('file_exists', False):
            return {"passed": False, "score": 0, "feedback": "Configuration file not found"}
            
        if not result.get('file_modified', False):
            return {"passed": False, "score": 0, "feedback": "Configuration file was not modified (do nothing detected)"}

        if result.get('is_valid_php', False):
            score += 20
            feedback_parts.append("File syntax is valid")
        else:
            feedback_parts.append("File has invalid PHP syntax")
            # If syntax is invalid, we might fail to parse, but let's try anyway
            
        # Decode content
        try:
            content_b64 = result.get('config_content_b64', '')
            content = base64.b64decode(content_b64).decode('utf-8')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to decode file content: {str(e)}"}

        # Parse trusted_hosts
        trusted_hosts = parse_php_ini_array(content, 'trusted_hosts')
        logger.info(f"Found trusted_hosts: {trusted_hosts}")
        
        # 2. Check for new host (40 pts)
        # Normalize for comparison
        trusted_hosts_norm = [h.lower().strip().strip('"\'') for h in trusted_hosts]
        
        if expected_host.lower() in trusted_hosts_norm:
            score += 40
            feedback_parts.append(f"'{expected_host}' added successfully")
        else:
            feedback_parts.append(f"'{expected_host}' NOT found in configuration")

        # 3. Check preservation (40 pts total)
        for host in required_hosts:
            if host.lower() in trusted_hosts_norm:
                score += 20
                feedback_parts.append(f"'{host}' preserved")
            else:
                feedback_parts.append(f"CRITICAL: '{host}' was removed!")

        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}