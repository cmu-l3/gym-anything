#!/usr/bin/env python3
"""
Verifier for PII Redaction Task.

Checks:
1. Filebeat service is running.
2. Verification marker log was found in the indexer (pipeline is working).
3. The 'cc_number' field is MISSING from the indexed marker (redaction successful).
4. The 'amount' field is PRESENT in the indexed marker (data integrity).
5. Filebeat configuration contains a processor instruction.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pii_redaction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    passed = False

    # Extract data
    indexer_response = result.get("indexer_response", {})
    filebeat_status = result.get("filebeat_status", "unknown")
    filebeat_config = result.get("filebeat_config", "")
    test_id = result.get("test_id", "")

    # 1. Check Service Health (20 pts)
    if filebeat_status == "running":
        score += 20
        feedback.append("Filebeat service is running.")
    else:
        feedback.append("Filebeat service is NOT running.")

    # 2. Check Configuration (20 pts)
    # Looking for 'processors' and 'drop_fields' or 'drop_event' or similar
    if "processors" in filebeat_config and ("drop_fields" in filebeat_config or "script" in filebeat_config):
        score += 20
        feedback.append("Filebeat configuration contains processors.")
    elif "processors" in filebeat_config:
        score += 10
        feedback.append("Filebeat configuration has processors, but 'drop_fields' not explicitly detected (manual check recommended).")
    else:
        feedback.append("Filebeat configuration does not appear to have processors configured.")

    # 3. Analyze Indexer Data (60 pts)
    hits = indexer_response.get("hits", {}).get("hits", [])
    
    if not hits:
        feedback.append("Verification marker log was NOT found in the indexer. The pipeline may be broken or blocked.")
        # If pipeline is broken, they fail the redaction check too
    else:
        # We found the log!
        log_source = hits[0].get("_source", {})
        log_data = log_source.get("data", {})
        
        # Check integrity (control field)
        if "amount" in log_data or "amount" in log_source:
             # 'amount' might be in root if decoding failed, but usually in 'data' for JSON
            score += 20
            feedback.append("Pipeline integrity verified: 'amount' field is present.")
        else:
            feedback.append("Pipeline integrity warning: 'amount' field is missing.")

        # Check Redaction (CRITICAL)
        # Should NOT have cc_number
        has_cc_in_data = "cc_number" in log_data
        has_cc_in_root = "cc_number" in log_source
        
        if not has_cc_in_data and not has_cc_in_root:
            score += 40
            feedback.append("SUCCESS: 'cc_number' field was successfully redacted.")
        else:
            feedback.append("FAILURE: 'cc_number' field is STILL PRESENT in the logs.")

    # Pass Condition
    # Must have service running + logs flowing + redaction working
    if score >= 80:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }