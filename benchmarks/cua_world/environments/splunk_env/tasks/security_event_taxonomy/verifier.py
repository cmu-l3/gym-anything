#!/usr/bin/env python3
"""Verifier for security_event_taxonomy task.

Multi-Criteria Evaluation:
1. Eventtype 'ssh_brute_force' correct (20 points)
2. Eventtype 'ssh_successful_login' correct (20 points)
3. Eventtype 'system_error' correct (20 points)
4. Tags correctly assigned across all eventtypes (20 points)
5. Saved search 'Tagged_Security_Summary' aggregates correctly (20 points)

Includes VLM trajectory verification to ensure UI usage.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# VLM PROMPT FOR UI VERIFICATION
UI_VERIFICATION_PROMPT = """You are evaluating a Splunk agent's trajectory for creating a security taxonomy.

The agent was tasked with:
1. Creating eventtypes (ssh_brute_force, ssh_successful_login, system_error)
2. Assigning tags to these eventtypes
3. Creating a saved search/report (Tagged_Security_Summary)

Look at the provided trajectory screenshots and determine:
1. Did the agent use the Splunk web UI to navigate to Settings > Event types, Settings > Tags, or the Search page?
2. Is there visual evidence of eventtypes being created or edited?
3. Is there visual evidence of a search being run or saved?

Respond in JSON format:
{
    "used_splunk_ui": true/false,
    "interacted_with_eventtypes": true/false,
    "interacted_with_search": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""


def verify_security_event_taxonomy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_ets = metadata.get('eventtypes', [])
    
    # Read result from container
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

    analysis = result.get('analysis', {})
    eventtypes = analysis.get('eventtypes', {})
    tags_conf = analysis.get('tags_conf', {})
    saved_search = analysis.get('saved_search', {})

    score = 0
    feedback_parts = []
    
    # Helper for checking tags
    def has_tag(et_name, tag):
        # Check eventtype tags field
        et_data = eventtypes.get(et_name, {})
        if tag.lower() in et_data.get('tags', '').lower():
            return True
        # Check tags.conf mappings
        conf_key = f"eventtype={et_name}"
        conf_data = tags_conf.get(conf_key, {})
        if conf_data.get(tag) == 'enabled' or conf_data.get(tag) == '1':
            return True
        return False

    # Check Eventtype 1: ssh_brute_force
    et1 = eventtypes.get('ssh_brute_force', {})
    if et1:
        search = et1.get('search', '').lower()
        if 'security_logs' in search and 'fail' in search:
            score += 20
            feedback_parts.append("ssh_brute_force correct")
        else:
            score += 10
            feedback_parts.append("ssh_brute_force partially correct (missing index or keyword)")
    else:
        feedback_parts.append("ssh_brute_force missing")

    # Check Eventtype 2: ssh_successful_login
    et2 = eventtypes.get('ssh_successful_login', {})
    if et2:
        search = et2.get('search', '').lower()
        if 'security_logs' in search and ('accept' in search or 'success' in search):
            score += 20
            feedback_parts.append("ssh_successful_login correct")
        else:
            score += 10
            feedback_parts.append("ssh_successful_login partially correct")
    else:
        feedback_parts.append("ssh_successful_login missing")

    # Check Eventtype 3: system_error
    et3 = eventtypes.get('system_error', {})
    if et3:
        search = et3.get('search', '').lower()
        if 'system_logs' in search and 'error' in search:
            score += 20
            feedback_parts.append("system_error correct")
        else:
            score += 10
            feedback_parts.append("system_error partially correct")
    else:
        feedback_parts.append("system_error missing")

    # Check Tags
    total_tags_required = 6
    tags_found = 0
    
    for et_meta in expected_ets:
        et_name = et_meta['name']
        for tag in et_meta['tags']:
            if has_tag(et_name, tag):
                tags_found += 1
                
    tag_score = int((tags_found / total_tags_required) * 20)
    score += tag_score
    feedback_parts.append(f"Tags: {tags_found}/{total_tags_required} correct")

    # Check Saved Search
    if saved_search:
        ss_search = saved_search.get('search', '').lower()
        if 'tag=authentication' in ss_search or 'tag::eventtype=' in ss_search or 'tag=' in ss_search:
            score += 20
            feedback_parts.append("Tagged_Security_Summary correct")
        else:
            score += 10
            feedback_parts.append("Tagged_Security_Summary exists but missing tag search")
    else:
        feedback_parts.append("Tagged_Security_Summary missing")

    # VLM Verification
    vlm_passed = False
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            try:
                vlm_res = query_vlm(prompt=UI_VERIFICATION_PROMPT, images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_splunk_ui', False):
                        vlm_passed = True
                        feedback_parts.append("VLM confirmed UI usage")
                    else:
                        feedback_parts.append("VLM indicated Splunk UI was not used")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

    # Final pass logic (require at least 60 points)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "tags_found": tags_found,
            "total_tags": total_tags_required,
            "vlm_passed": vlm_passed
        }
    }