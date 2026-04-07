#!/usr/bin/env python3
"""Verifier for incident_response_workflow_actions task.

Verification Strategy (Hybrid):
1. Checks programmatic Splunk REST API artifacts for Workflow Actions & Saved Searches.
2. Checks VLM Trajectory to ensure the agent actually used the Web UI to configure them.

Passing Threshold: 60/100 points
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_UI_PROMPT = """You are analyzing a sequence of screenshots from an agent interacting with Splunk.
The agent's goal was to create "Workflow actions" and a "Saved Search" in the Splunk Web UI.

Assess the agent's actions across these frames:
1. Did the agent navigate to Settings > Fields > Workflow actions?
2. Is there evidence of the agent filling out a Workflow Action configuration form (e.g., entering "AbuseIPDB_Check" or a URI like "abuseipdb.com")?
3. Did the agent use the Splunk Web Interface (browser) rather than just a terminal?

Respond strictly in JSON format:
{
    "used_splunk_web_ui": true/false,
    "interacted_with_workflow_actions": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of visible UI interactions"
}
"""

def normalize_name(name):
    """Normalize object names for comparison (case-insensitive, underscores)."""
    return name.lower().replace(' ', '_').replace('-', '_')

def verify_workflow_actions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_wa_1 = normalize_name(metadata.get('expected_wa_1', 'AbuseIPDB_Check'))
    expected_wa_2 = normalize_name(metadata.get('expected_wa_2', 'Deep_IP_Investigation'))
    expected_ss_1 = normalize_name(metadata.get('expected_ss_1', 'Top_Attacking_IPs'))

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    workflow_actions = analysis.get('workflow_actions', [])
    saved_searches = analysis.get('saved_searches', [])

    score = 0
    feedback_parts = []
    subscores = {}

    # Find the expected artifacts by name
    abuse_wa = next((wa for wa in workflow_actions if normalize_name(wa.get('name', '')) == expected_wa_1), None)
    deep_ip_wa = next((wa for wa in workflow_actions if normalize_name(wa.get('name', '')) == expected_wa_2), None)
    top_ips_ss = next((ss for ss in saved_searches if normalize_name(ss.get('name', '')) == expected_ss_1), None)

    # 1. AbuseIPDB_Check workflow action (Exists + Correct type/URI)
    if abuse_wa:
        score += 10
        feedback_parts.append(f"Found WA: {expected_wa_1}")
        subscores['abuse_wa_exists'] = True
        
        uri = abuse_wa.get('link_uri', '').lower()
        wa_type = abuse_wa.get('type', '').lower()
        
        if 'abuseipdb.com' in uri and '$' in uri:
            score += 15
            feedback_parts.append("AbuseIPDB WA has correct URL and token")
            subscores['abuse_wa_url_correct'] = True
        else:
            feedback_parts.append("AbuseIPDB WA missing correct domain or '$' token in URI")
            subscores['abuse_wa_url_correct'] = False
    else:
        feedback_parts.append(f"FAIL: Missing WA '{expected_wa_1}'")
        subscores['abuse_wa_exists'] = False
        subscores['abuse_wa_url_correct'] = False

    # 2. Deep_IP_Investigation workflow action (Exists + Search logic)
    if deep_ip_wa:
        score += 10
        feedback_parts.append(f"Found WA: {expected_wa_2}")
        subscores['deep_ip_wa_exists'] = True
        
        search_str = deep_ip_wa.get('search_string', '').lower()
        wa_type = deep_ip_wa.get('type', '').lower()
        
        # Check if it has an index wildcard or references multiple indexes, and has a token
        has_multi_index = 'index=*' in search_str or 'index = *' in search_str or search_str.count('index') >= 2
        has_token = '$' in search_str
        
        if (wa_type == 'search' or search_str) and has_multi_index and has_token:
            score += 20
            feedback_parts.append("Deep_IP WA configured as multi-index search with token")
            subscores['deep_ip_wa_search_correct'] = True
        else:
            feedback_parts.append("Deep_IP WA search string lacks token or multi-index logic")
            subscores['deep_ip_wa_search_correct'] = False
    else:
        feedback_parts.append(f"FAIL: Missing WA '{expected_wa_2}'")
        subscores['deep_ip_wa_exists'] = False
        subscores['deep_ip_wa_search_correct'] = False

    # 3. Top_Attacking_IPs saved search
    if top_ips_ss:
        score += 10
        feedback_parts.append(f"Found Saved Search: {expected_ss_1}")
        subscores['top_ips_ss_exists'] = True
        
        search_str = top_ips_ss.get('search', '').lower()
        
        if 'security_logs' in search_str and ('stats' in search_str or 'count' in search_str):
            score += 15
            feedback_parts.append("Saved Search queries security_logs with aggregation")
            subscores['top_ips_ss_logic_correct'] = True
        else:
            feedback_parts.append("Saved Search missing 'security_logs' or aggregation")
            subscores['top_ips_ss_logic_correct'] = False
    else:
        feedback_parts.append(f"FAIL: Missing Saved Search '{expected_ss_1}'")
        subscores['top_ips_ss_exists'] = False
        subscores['top_ips_ss_logic_correct'] = False

    # 4. Anti-Gaming check: Ensure they are newly created
    new_items = any([
        abuse_wa and abuse_wa.get('is_new'),
        deep_ip_wa and deep_ip_wa.get('is_new'),
        top_ips_ss and top_ips_ss.get('is_new')
    ])
    
    if not new_items and score > 0:
        score = 0
        feedback_parts.append("FAIL: Detected pre-existing items. Agent did not create them during this session.")
        subscores['new_items_created'] = False
    else:
        subscores['new_items_created'] = True

    # 5. VLM Trajectory Process Verification
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_res = query_vlm(prompt=VLM_UI_PROMPT, images=frames)
                if vlm_res and vlm_res.get('success'):
                    vlm_parsed = vlm_res.get('parsed', {})
                    if vlm_parsed.get('used_splunk_web_ui'):
                        vlm_score += 10
                    if vlm_parsed.get('interacted_with_workflow_actions'):
                        vlm_score += 10
                        
                    feedback_parts.append(f"VLM UI check: {vlm_score}/20 pts")
                else:
                    logger.warning("VLM query did not return success")
        except Exception as e:
            logger.error(f"VLM UI verification failed: {e}")
            feedback_parts.append("VLM verification skipped/failed")
    
    score += vlm_score

    # Final logic
    passed = score >= 60 and subscores.get('new_items_created', False) and (subscores.get('abuse_wa_exists') or subscores.get('deep_ip_wa_exists'))

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "vlm_score": vlm_score,
            "new_wa_count": sum(1 for wa in workflow_actions if wa.get('is_new')),
            "new_ss_count": sum(1 for ss in saved_searches if ss.get('is_new'))
        }
    }