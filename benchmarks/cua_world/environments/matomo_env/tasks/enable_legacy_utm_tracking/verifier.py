#!/usr/bin/env python3
"""
Verifier for Enable Legacy UTM Tracking task.

Verification Strategy:
1. Decode the base64 config file content exported from the container.
2. Parse the INI structure.
3. Check the [Tracker] section for specific keys.
4. Verify that each key contains BOTH the default parameter (pk_*) AND the UTM parameter (utm_*).
5. Verify that the file was actually modified during the task window.
"""

import json
import logging
import os
import tempfile
import base64
import configparser
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_legacy_utm_tracking(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify Matomo configuration for legacy UTM tracking parameters.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected requirements from metadata
    metadata = task_info.get('metadata', {})
    required_params = metadata.get('required_params', {
        "campaign_var_name": ["pk_campaign", "utm_campaign"],
        "campaign_keyword_var_name": ["pk_kwd", "utm_term"],
        "campaign_source_var_name": ["pk_source", "utm_source"],
        "campaign_medium_var_name": ["pk_medium", "utm_medium"],
        "campaign_content_var_name": ["pk_content", "utm_content"],
        "campaign_id_var_name": ["pk_id", "utm_id"]
    })
    
    scoring_weights = metadata.get('scoring_weights', {
        "campaign_name": 15,
        "campaign_source": 15,
        "campaign_medium": 15,
        "campaign_keyword": 15,
        "campaign_content": 15,
        "campaign_id": 10,
        "defaults_preserved": 15
    })

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Config file not found in container."}
    
    if not result.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Config file was not modified during the task."}

    # Parse Config content
    config_content_b64 = result.get('config_content_base64', "")
    if not config_content_b64:
        return {"passed": False, "score": 0, "feedback": "Config content is empty."}
    
    try:
        config_text = base64.b64decode(config_content_b64).decode('utf-8')
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to decode config content: {e}"}

    # Python's ConfigParser is strict about structure. Matomo config is mostly PHP-compatible INI.
    # We'll try to parse it, but handle potential issues with PHP specific syntax if any.
    # PHP INI allows quoting values which ConfigParser handles well.
    
    config = configparser.ConfigParser(strict=False)
    try:
        config.read_string(config_text)
    except configparser.Error as e:
        # Fallback: simple string search if parser fails (though Matomo config is usually clean)
        logger.warning(f"ConfigParser failed, using simple text search: {e}")
        config = None

    # Helper to get value
    def get_tracker_value(key):
        if config and 'Tracker' in config:
            return config['Tracker'].get(key, "").replace('"', '').replace("'", "")
        else:
            # Fallback text parsing
            # Look for lines like: key = "value"
            for line in config_text.splitlines():
                if line.strip().startswith(key):
                    parts = line.split('=', 1)
                    if len(parts) > 1:
                        # strip comments and quotes
                        val = parts[1].split(';')[0].strip().strip('"').strip("'")
                        return val
        return ""

    score = 0
    feedback_parts = []
    defaults_preserved_count = 0
    total_params = len(required_params)
    
    # Evaluate each parameter
    for param_key, expected_values in required_params.items():
        actual_value = get_tracker_value(param_key)
        actual_parts = [p.strip() for p in actual_value.split(',')]
        
        pk_val = expected_values[0] # The default Matomo param (e.g., pk_campaign)
        utm_val = expected_values[1] # The legacy UTM param (e.g., utm_campaign)
        
        has_pk = pk_val in actual_parts
        has_utm = utm_val in actual_parts
        
        # Determine score component based on param name mapping to weights
        weight_key = ""
        if "campaign_var_name" == param_key: weight_key = "campaign_name"
        elif "source" in param_key: weight_key = "campaign_source"
        elif "medium" in param_key: weight_key = "campaign_medium"
        elif "keyword" in param_key: weight_key = "campaign_keyword"
        elif "content" in param_key: weight_key = "campaign_content"
        elif "id" in param_key: weight_key = "campaign_id"
        
        param_score = scoring_weights.get(weight_key, 0)
        
        if has_utm:
            score += param_score
            feedback_parts.append(f"{param_key}: UTM configured")
        else:
            feedback_parts.append(f"{param_key}: Missing UTM tag ({utm_val})")
            
        if has_pk:
            defaults_preserved_count += 1
        else:
            feedback_parts.append(f"{param_key}: Default tag removed ({pk_val})")

    # Score for preserving defaults
    if defaults_preserved_count == total_params:
        score += scoring_weights.get("defaults_preserved", 15)
        feedback_parts.append("All defaults preserved")
    else:
        feedback_parts.append(f"Some defaults removed ({total_params - defaults_preserved_count})")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }