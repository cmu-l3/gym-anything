#!/usr/bin/env python3
"""
Verifier for conditional_sourcetype_routing task.

Verification Strategy:
Dynamic functional testing. The export script injects 3 live syslog payloads into 
UDP:5140 with a random Evaluation ID and queries Splunk's REST API to see how 
the ingestion pipeline categorized them. This perfectly prevents gaming and accurately 
tests index-time (transforms/props) configurations.

Criteria:
1. Splunk is running and healthy (10 pts)
2. UDP port received logs and routed them to `system_logs` (20 pts)
3. Default payload correctly received `legacy_app` sourcetype (10 pts)
4. [CRITICAL] payload was dynamically overridden to `legacy_app_critical` (30 pts)
5. [WARN] payload was dynamically overridden to `legacy_app_warn` (30 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_conditional_sourcetype_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_index = metadata.get('target_index', 'system_logs')
    base_st = metadata.get('base_sourcetype', 'legacy_app')
    crit_st = metadata.get('critical_sourcetype', 'legacy_app_critical')
    warn_st = metadata.get('warn_sourcetype', 'legacy_app_warn')

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

    splunk_running = result.get('splunk_running', False)
    search_results = result.get('results', [])
    configs = result.get('configs', {})

    score = 0
    feedback_parts = []
    
    # Criterion 1: Splunk Health
    if splunk_running:
        score += 10
        feedback_parts.append("Splunk service is running")
    else:
        feedback_parts.append("FAIL: Splunk service is not running (did agent restart it after config changes?)")
        
    # Analyze ingestion results
    info_found, crit_found, warn_found = False, False, False
    info_idx, crit_idx, warn_idx = "", "", ""
    info_st, crit_st_actual, warn_st_actual = "", "", ""
    
    for r in search_results:
        raw = r.get('_raw', '')
        idx = r.get('index', '')
        st = r.get('sourcetype', '')
        
        if '[INFO]' in raw:
            info_found = True
            info_idx = idx
            info_st = st
        elif '[CRITICAL]' in raw:
            crit_found = True
            crit_idx = idx
            crit_st_actual = st
        elif '[WARN]' in raw:
            warn_found = True
            warn_idx = idx
            warn_st_actual = st

    # Criterion 2: UDP Input & Index Routing (Base)
    if info_found:
        if info_idx == target_index:
            score += 20
            feedback_parts.append(f"UDP input active and routing to {target_index}")
        else:
            feedback_parts.append(f"FAIL: Logs ingested, but routed to index '{info_idx}' instead of '{target_index}'")
    else:
        feedback_parts.append("FAIL: No logs ingested on UDP 5140 (input missing or wrong port)")

    # Criterion 3: Default Sourcetype
    if info_found and info_st == base_st:
        score += 10
        feedback_parts.append(f"Default sourcetype correctly set to '{base_st}'")
    elif info_found:
        feedback_parts.append(f"FAIL: Default sourcetype is '{info_st}', expected '{base_st}'")

    # Criterion 4: Critical Dynamic Routing
    if crit_found and crit_st_actual == crit_st:
        score += 30
        feedback_parts.append(f"Critical payloads successfully transformed to '{crit_st}'")
    elif crit_found:
        feedback_parts.append(f"FAIL: Critical payloads failed to transform (stayed as '{crit_st_actual}')")

    # Criterion 5: Warn Dynamic Routing
    if warn_found and warn_st_actual == warn_st:
        score += 30
        feedback_parts.append(f"Warn payloads successfully transformed to '{warn_st}'")
    elif warn_found:
        feedback_parts.append(f"FAIL: Warn payloads failed to transform (stayed as '{warn_st_actual}')")

    # Fallback Partial Credit: If Splunk broke or didn't restart, check config text directly
    if score < 50:
        inputs_txt = configs.get('inputs', '')
        props_txt = configs.get('props', '')
        trans_txt = configs.get('transforms', '')
        
        fallback_msg = "Checking configuration files directly due to ingestion failure: "
        sub_msgs = []
        if '[udp://5140]' in inputs_txt:
            score = max(score, score + 5)
            sub_msgs.append("inputs.conf has [udp://5140]")
        if '[legacy_app]' in props_txt and 'TRANSFORMS' in props_txt:
            score = max(score, score + 10)
            sub_msgs.append("props.conf has legacy_app transforms")
        if 'DEST_KEY' in trans_txt and 'MetaData:Sourcetype' in trans_txt:
            score = max(score, score + 10)
            sub_msgs.append("transforms.conf has sourcetype routing definitions")
            
        if sub_msgs:
            feedback_parts.append(fallback_msg + ", ".join(sub_msgs))

    # Pass condition
    passed = score >= 80

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }