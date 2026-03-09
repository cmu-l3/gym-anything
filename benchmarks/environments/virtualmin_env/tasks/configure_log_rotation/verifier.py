#!/usr/bin/env python3
"""
Verifier for configure_log_rotation task.

Verification Logic:
1. Check if the logrotate configuration file exists for the domain.
2. Parse the configuration to find the block for '/var/log/virtualmin/acmecorp.test_access_log'.
3. Verify 'daily' rotation is present.
4. Verify 'rotate 30' is present.
5. Verify 'compress' is present.
6. Verify the file was modified during the task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_log_rotation(traj, env_info, task_info):
    """
    Verify log rotation settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_log = metadata.get('log_file_path', '/var/log/virtualmin/acmecorp.test_access_log')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
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

    if not result.get('config_found'):
        return {"passed": False, "score": 0, "feedback": "Logrotate configuration file not found on server."}

    # 2. Retrieve Config File content
    # We copied it to /tmp/final_logrotate.conf in export_result.sh
    temp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.conf')
    try:
        copy_from_env("/tmp/final_logrotate.conf", temp_conf.name)
        with open(temp_conf.name, 'r') as f:
            config_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve config file: {e}"}
    finally:
        if os.path.exists(temp_conf.name):
            os.unlink(temp_conf.name)

    # 3. Parse Config Content
    # The file might contain multiple blocks. We need to find the one for our target log.
    # Format typically:
    # /path/to/log {
    #    daily
    #    rotate 30
    #    ...
    # }
    
    # Regex to extract the block content
    # Look for the log path, followed by opening brace, capturing everything until closing brace
    # Non-greedy match for content
    pattern = re.compile(re.escape(target_log) + r"\s*\{([^}]+)\}", re.MULTILINE | re.DOTALL)
    match = pattern.search(config_content)
    
    if not match:
        feedback_parts.append(f"Could not find configuration block for {target_log}")
        # Try finding it without the full path if strict match fails (sometimes relative or grouped)
        # But for Virtualmin standard setup, full path is standard.
    else:
        block_content = match.group(1)
        feedback_parts.append("Found log configuration block")
        
        # Check Daily
        if re.search(r'\bdaily\b', block_content):
            score += 25
            feedback_parts.append("Schedule: Daily (Correct)")
        else:
            feedback_parts.append("Schedule: Incorrect (Expected 'daily')")

        # Check Rotate 30
        rotate_match = re.search(r'\brotate\s+(\d+)\b', block_content)
        if rotate_match:
            val = int(rotate_match.group(1))
            if val == 30:
                score += 25
                feedback_parts.append("Retention: 30 (Correct)")
            else:
                feedback_parts.append(f"Retention: {val} (Expected 30)")
        else:
            feedback_parts.append("Retention: Not set")

        # Check Compress
        # Look for 'compress' but NOT 'nocompress' active (though 'nocompress' overrides)
        # Usually just checking for presence of 'compress' line is enough if we assume standard format
        if re.search(r'\bcompress\b', block_content) and not re.search(r'\bnocompress\b', block_content):
            score += 25
            feedback_parts.append("Compression: Enabled (Correct)")
        else:
            feedback_parts.append("Compression: Disabled/Missing")

    # 4. Check Modification Timestamp (Anti-gaming)
    if result.get('file_modified_during_task'):
        score += 25
        feedback_parts.append("Configuration saved during task")
    else:
        feedback_parts.append("Configuration file not modified during task (did you save?)")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }