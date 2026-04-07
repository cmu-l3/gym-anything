#!/usr/bin/env python3
"""Verifier for configure_hec_tokens task.

CRITERIA & SCORING (Total: 100 points):
1. HEC globally enabled (15 pts)
2. 'cloud_apps' index exists (15 pts)
3. 'webapp_frontend' token exists and is enabled (20 pts)
4. 'webapp_frontend' targets the correct index (5 pts)
5. 'webapp_backend' token exists and is enabled (20 pts)
6. 'webapp_backend' targets the correct index (5 pts)
7. Test event successfully ingested into 'cloud_apps' (20 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_token_enabled(token_content):
    """Helper to check if a token dictionary indicates it is enabled."""
    disabled = token_content.get('disabled', True)
    if isinstance(disabled, bool):
        return not disabled
    return str(disabled).lower() in ['0', 'false']


def check_token_index(token_content, expected_index):
    """Helper to verify if the token specifies the correct index."""
    idx = token_content.get('index', '')
    indexes = token_content.get('indexes', '')
    
    # Check default index field
    if idx == expected_index:
        return True
    
    # Check allowed indexes list
    if indexes and expected_index in indexes.split(','):
        return True
        
    return False


def verify_configure_hec_tokens(traj, env_info, task_info):
    """Verify that the HEC infrastructure was successfully configured."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_index = metadata.get('expected_index', 'cloud_apps')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: HEC Globally Enabled (15 pts)
    if result.get('hec_globally_enabled', False):
        score += 15
        feedback_parts.append("HEC is globally enabled (+15)")
        subscores['hec_enabled'] = True
    else:
        feedback_parts.append("FAIL: HEC is not globally enabled")
        subscores['hec_enabled'] = False

    # Criterion 2: 'cloud_apps' index exists (15 pts)
    if result.get('cloud_apps_index_exists', False):
        score += 15
        feedback_parts.append(f"Index '{expected_index}' exists (+15)")
        subscores['index_exists'] = True
    else:
        feedback_parts.append(f"FAIL: Index '{expected_index}' does not exist")
        subscores['index_exists'] = False

    # Check Tokens
    frontend_token = result.get('frontend_token')
    backend_token = result.get('backend_token')

    # Criterion 3 & 4: Frontend Token (20 pts + 5 pts)
    if frontend_token:
        if is_token_enabled(frontend_token):
            score += 20
            feedback_parts.append("Frontend token exists and is enabled (+20)")
            subscores['frontend_enabled'] = True
        else:
            feedback_parts.append("Frontend token exists but is DISABLED")
            subscores['frontend_enabled'] = False

        if check_token_index(frontend_token, expected_index):
            score += 5
            feedback_parts.append("Frontend token maps to correct index (+5)")
            subscores['frontend_index_correct'] = True
        else:
            idx = frontend_token.get('index', 'none')
            feedback_parts.append(f"FAIL: Frontend token maps to wrong index '{idx}'")
            subscores['frontend_index_correct'] = False
    else:
        feedback_parts.append("FAIL: Frontend token not found")
        subscores['frontend_enabled'] = False
        subscores['frontend_index_correct'] = False

    # Criterion 5 & 6: Backend Token (20 pts + 5 pts)
    if backend_token:
        if is_token_enabled(backend_token):
            score += 20
            feedback_parts.append("Backend token exists and is enabled (+20)")
            subscores['backend_enabled'] = True
        else:
            feedback_parts.append("Backend token exists but is DISABLED")
            subscores['backend_enabled'] = False

        if check_token_index(backend_token, expected_index):
            score += 5
            feedback_parts.append("Backend token maps to correct index (+5)")
            subscores['backend_index_correct'] = True
        else:
            idx = backend_token.get('index', 'none')
            feedback_parts.append(f"FAIL: Backend token maps to wrong index '{idx}'")
            subscores['backend_index_correct'] = False
    else:
        feedback_parts.append("FAIL: Backend token not found")
        subscores['backend_enabled'] = False
        subscores['backend_index_correct'] = False

    # Criterion 7: Event Ingestion (20 pts)
    event_count = result.get('event_count', 0)
    if event_count > 0:
        score += 20
        feedback_parts.append(f"Test events successfully ingested (count: {event_count}) (+20)")
        subscores['events_ingested'] = True
    else:
        feedback_parts.append("FAIL: No test events ingested into cloud_apps index")
        subscores['events_ingested'] = False

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "event_count": event_count,
            "frontend_configured": frontend_token is not None,
            "backend_configured": backend_token is not None
        }
    }