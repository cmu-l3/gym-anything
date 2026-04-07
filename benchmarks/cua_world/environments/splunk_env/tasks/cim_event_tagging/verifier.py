#!/usr/bin/env python3
"""Verifier for cim_event_tagging task.

Checks:
1. `ssh_failed_login` eventtype exists and maps correctly (15 pts)
2. Tags `authentication`, `failure` applied to `ssh_failed_login` (20 pts)
3. `apache_critical_error` eventtype exists and maps correctly (15 pts)
4. Tags `error`, `critical` applied to `apache_critical_error` (20 pts)
5. `Unified_SOC_Alerts` saved search exists (15 pts)
6. `Unified_SOC_Alerts` search explicitly uses `tag=` syntax (15 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_applied_tags(tags_data, eventtype_name):
    """
    Extract tags applied to an eventtype from the conf-tags REST payload.
    Splunk maps tags like name="eventtype=ssh_failed_login"
    with content={"authentication": "enabled", "failure": "enabled"}
    """
    target_name = f"eventtype={eventtype_name}".lower()
    applied = []
    
    for entry in tags_data:
        if entry.get('name', '').lower() == target_name:
            content = entry.get('content', {})
            # Look for keys where the value is "enabled"
            for k, v in content.items():
                if str(v).lower() == 'enabled':
                    applied.append(k.lower())
    return applied

def verify_cim_event_tagging(traj, env_info, task_info):
    """Verify that the agent correctly created CIM-compliant event types and tags."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_et1 = metadata.get('expected_et1', 'ssh_failed_login').lower()
    expected_et2 = metadata.get('expected_et2', 'apache_critical_error').lower()
    expected_ss = metadata.get('expected_search', 'Unified_SOC_Alerts').lower()

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/cim_event_tagging_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    eventtypes = result.get('eventtypes', [])
    tags_data = result.get('tags', [])
    saved_searches = result.get('saved_searches', [])

    score = 0
    feedback_parts = []
    subscores = {
        "et1_exists": False,
        "et1_tags": False,
        "et2_exists": False,
        "et2_tags": False,
        "ss_exists": False,
        "ss_uses_tags": False
    }

    # ==========================================
    # 1 & 2: SSH Eventtype and Tags (35 points)
    # ==========================================
    ssh_et = next((e for e in eventtypes if e.get('name', '').lower() == expected_et1), None)
    if ssh_et:
        search_query = ssh_et.get('content', {}).get('search', '').lower()
        if 'security_logs' in search_query and 'failed' in search_query:
            score += 15
            subscores["et1_exists"] = True
            feedback_parts.append("SSH event type created correctly")
            
            # Check Tags
            et1_tags = get_applied_tags(tags_data, expected_et1)
            # Sometimes tags are included directly in the eventtype content under 'tags'
            direct_tags = ssh_et.get('content', {}).get('tags', '')
            if isinstance(direct_tags, str):
                et1_tags.extend([t.strip().lower() for t in direct_tags.split() if t.strip()])
            elif isinstance(direct_tags, list):
                et1_tags.extend([t.lower() for t in direct_tags])
            
            has_auth = 'authentication' in et1_tags
            has_fail = 'failure' in et1_tags
            
            if has_auth and has_fail:
                score += 20
                subscores["et1_tags"] = True
                feedback_parts.append("SSH tags applied correctly")
            elif has_auth or has_fail:
                score += 10
                feedback_parts.append(f"Partial SSH tags applied: {et1_tags}")
            else:
                feedback_parts.append("FAIL: SSH tags missing")
        else:
            feedback_parts.append("FAIL: SSH event type exists but search string is incorrect")
    else:
        feedback_parts.append("FAIL: SSH event type not found")

    # ==========================================
    # 3 & 4: Apache Eventtype and Tags (35 points)
    # ==========================================
    apache_et = next((e for e in eventtypes if e.get('name', '').lower() == expected_et2), None)
    if apache_et:
        search_query = apache_et.get('content', {}).get('search', '').lower()
        if 'web_logs' in search_query and ('crit' in search_query or 'error' in search_query):
            score += 15
            subscores["et2_exists"] = True
            feedback_parts.append("Apache event type created correctly")
            
            # Check Tags
            et2_tags = get_applied_tags(tags_data, expected_et2)
            direct_tags = apache_et.get('content', {}).get('tags', '')
            if isinstance(direct_tags, str):
                et2_tags.extend([t.strip().lower() for t in direct_tags.split() if t.strip()])
            elif isinstance(direct_tags, list):
                et2_tags.extend([t.lower() for t in direct_tags])
                
            has_error = 'error' in et2_tags
            has_crit = 'critical' in et2_tags
            
            if has_error and has_crit:
                score += 20
                subscores["et2_tags"] = True
                feedback_parts.append("Apache tags applied correctly")
            elif has_error or has_crit:
                score += 10
                feedback_parts.append(f"Partial Apache tags applied: {et2_tags}")
            else:
                feedback_parts.append("FAIL: Apache tags missing")
        else:
            feedback_parts.append("FAIL: Apache event type exists but search string is incorrect")
    else:
        feedback_parts.append("FAIL: Apache event type not found")

    # ==========================================
    # 5 & 6: Saved Search uses tags (30 points)
    # ==========================================
    target_ss = next((s for s in saved_searches if s.get('name', '').lower() == expected_ss), None)
    if target_ss:
        score += 15
        subscores["ss_exists"] = True
        
        ss_query = target_ss.get('content', {}).get('search', '').lower()
        if 'tag=' in ss_query or 'tag =' in ss_query or 'tag IN' in ss_query:
            score += 15
            subscores["ss_uses_tags"] = True
            feedback_parts.append("Unified_SOC_Alerts exists and uses tags")
        else:
            feedback_parts.append("FAIL: Unified_SOC_Alerts exists but does NOT use tag= syntax")
    else:
        feedback_parts.append("FAIL: Unified_SOC_Alerts saved search not found")

    # Pass threshold: Must have scored at least 70, and successfully created the search using tags
    key_criteria_met = subscores["ss_uses_tags"] and (subscores["et1_exists"] or subscores["et2_exists"])
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }