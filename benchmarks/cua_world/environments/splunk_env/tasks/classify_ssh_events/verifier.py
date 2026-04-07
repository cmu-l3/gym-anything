#!/usr/bin/env python3
"""Verifier for classify_ssh_events task.

Checks for proper creation and configuration of Splunk Knowledge Objects:
1. Event type: failed_ssh_authentication (search must contain security_logs and fail keywords)
2. Event type: successful_ssh_authentication (search must contain security_logs and success keywords)
3. Tags: 'authentication' and 'attack' applied to failed; 'authentication' applied to success.
4. Saved Report: SSH_Authentication_Summary exists.
5. Saved Report: search contains security_logs and an aggregation command.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

POINTS_PER_CRITERION = 20
PASS_THRESHOLD = 60

def normalize_name(name):
    """Normalize object name for comparison."""
    return name.lower().strip().replace(' ', '_').replace('-', '_')

def get_tags_for_eventtype(tags_data, eventtype_name):
    """Extract tags applied to a specific event type from conf-tags API response."""
    # In Splunk, tags are stored in conf-tags with stanza names like "eventtype=my_event_type"
    target_name1 = f"eventtype={eventtype_name}".lower()
    target_name2 = f"eventtype%3d{eventtype_name}".lower()  # URL encoded variant
    
    found_tags = set()
    for t in tags_data:
        t_name = t.get('name', '').lower()
        if t_name == target_name1 or t_name == target_name2:
            content = t.get('content', {})
            for k, v in content.items():
                if v == 'enabled' and not k.startswith('eai:'):
                    found_tags.add(k.lower())
    return found_tags

def verify_classify_ssh_events(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_fail_name = normalize_name(metadata.get('event_type_fail', 'failed_ssh_authentication'))
    expected_success_name = normalize_name(metadata.get('event_type_success', 'successful_ssh_authentication'))
    expected_report_name = normalize_name(metadata.get('report_name', 'SSH_Authentication_Summary'))

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    initial_state = analysis.get('initial_state', {})
    eventtypes = analysis.get('eventtypes', [])
    tags_data = analysis.get('tags', [])
    searches = analysis.get('searches', [])

    initial_eventtypes = [normalize_name(n) for n in initial_state.get('eventtypes', []) if n]
    initial_searches = [normalize_name(n) for n in initial_state.get('searches', []) if n]

    score = 0
    feedback = []
    subscores = {}

    # CRITERION 1: Failed SSH Event Type
    failed_et = next((e for e in eventtypes if normalize_name(e.get('name', '')) == expected_fail_name), None)
    if failed_et:
        search_str = failed_et.get('search', '').lower()
        if expected_fail_name in initial_eventtypes:
            feedback.append("FAIL: 'failed_ssh_authentication' existed before task started.")
            subscores['failed_event_type'] = False
        elif 'security_logs' in search_str and ('fail' in search_str or 'invalid' in search_str):
            score += POINTS_PER_CRITERION
            feedback.append("Failed SSH event type created successfully.")
            subscores['failed_event_type'] = True
        else:
            feedback.append(f"FAIL: 'failed_ssh_authentication' search lacks 'security_logs' or failure keyword (got: {search_str}).")
            subscores['failed_event_type'] = False
    else:
        feedback.append("FAIL: 'failed_ssh_authentication' event type not found.")
        subscores['failed_event_type'] = False

    # CRITERION 2: Successful SSH Event Type
    success_et = next((e for e in eventtypes if normalize_name(e.get('name', '')) == expected_success_name), None)
    if success_et:
        search_str = success_et.get('search', '').lower()
        if expected_success_name in initial_eventtypes:
            feedback.append("FAIL: 'successful_ssh_authentication' existed before task started.")
            subscores['success_event_type'] = False
        elif 'security_logs' in search_str and ('accept' in search_str or 'success' in search_str):
            score += POINTS_PER_CRITERION
            feedback.append("Successful SSH event type created successfully.")
            subscores['success_event_type'] = True
        else:
            feedback.append(f"FAIL: 'successful_ssh_authentication' search lacks 'security_logs' or success keyword (got: {search_str}).")
            subscores['success_event_type'] = False
    else:
        feedback.append("FAIL: 'successful_ssh_authentication' event type not found.")
        subscores['success_event_type'] = False

    # CRITERION 3: Tags
    tags_score = 0
    if failed_et:
        fail_tags = get_tags_for_eventtype(tags_data, failed_et.get('name'))
        if 'authentication' in fail_tags and 'attack' in fail_tags:
            tags_score += 10
            feedback.append("Tags 'authentication' and 'attack' found on failed event type.")
        else:
            feedback.append(f"FAIL: Missing expected tags on failed event type (found: {list(fail_tags)}).")

    if success_et:
        success_tags = get_tags_for_eventtype(tags_data, success_et.get('name'))
        if 'authentication' in success_tags:
            tags_score += 10
            feedback.append("Tag 'authentication' found on successful event type.")
        else:
            feedback.append(f"FAIL: Missing expected tags on successful event type (found: {list(success_tags)}).")

    score += tags_score
    subscores['tags'] = (tags_score == 20)

    # CRITERION 4: Saved Report Exists
    report = next((s for s in searches if normalize_name(s.get('name', '')) == expected_report_name), None)
    if report:
        if expected_report_name in initial_searches:
            feedback.append("FAIL: Report 'SSH_Authentication_Summary' existed before task started.")
            subscores['report_exists'] = False
            subscores['report_valid'] = False
        else:
            score += POINTS_PER_CRITERION
            feedback.append("Report 'SSH_Authentication_Summary' created successfully.")
            subscores['report_exists'] = True

            # CRITERION 5: Saved Report Content
            search_str = report.get('search', '').lower()
            agg_commands = ['| stats', '| timechart', '| chart', '| top', '| rare', '| eventstats']
            has_agg = any(cmd in search_str for cmd in agg_commands)
            
            if 'security_logs' in search_str and has_agg:
                score += POINTS_PER_CRITERION
                feedback.append("Report contains valid 'security_logs' reference and an aggregation command.")
                subscores['report_valid'] = True
            else:
                feedback.append(f"FAIL: Report search lacks 'security_logs' reference or aggregation command (got: {search_str[:80]}).")
                subscores['report_valid'] = False
    else:
        feedback.append("FAIL: Report 'SSH_Authentication_Summary' not found.")
        subscores['report_exists'] = False
        subscores['report_valid'] = False

    return {
        "passed": score >= PASS_THRESHOLD,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "failed_et_search": failed_et.get('search', '') if failed_et else "",
            "success_et_search": success_et.get('search', '') if success_et else "",
            "report_search": report.get('search', '') if report else ""
        }
    }