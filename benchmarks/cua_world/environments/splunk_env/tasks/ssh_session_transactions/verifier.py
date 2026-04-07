#!/usr/bin/env python3
"""Verifier for ssh_session_transactions task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ssh_session_transactions(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_search_name = metadata.get('saved_search_name', 'ssh_brute_force_sessions')
    expected_dash_name = metadata.get('dashboard_name', 'ssh_session_analysis')
    expected_index = metadata.get('index', 'security_logs')
    expected_command = metadata.get('command', 'transaction')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ssh_session_transactions_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    new_searches = analysis.get('new_searches', [])
    new_dashboards = analysis.get('new_dashboards', [])

    score = 0
    feedback = []
    subscores = {}

    # 1. Saved search exists
    target_search = None
    for s in new_searches:
        if s.get('normalized_name') == expected_search_name:
            target_search = s
            break
            
    if target_search:
        score += 20
        feedback.append(f"Saved search '{target_search['name']}' exists")
        subscores['saved_search_exists'] = True
    else:
        feedback.append(f"FAIL: Saved search '{expected_search_name}' not found")
        subscores['saved_search_exists'] = False
        target_search = new_searches[-1] if new_searches else {}

    search_text = target_search.get('search', '').lower()

    # 2. Uses transaction
    has_transaction = re.search(r'\|\s*transaction\b', search_text) or search_text.startswith('transaction')
    if has_transaction:
        score += 20
        feedback.append("Search uses 'transaction' command")
        subscores['uses_transaction'] = True
    else:
        feedback.append("FAIL: Search does not use the 'transaction' command")
        subscores['uses_transaction'] = False

    # 3. Targets security_logs
    if expected_index in search_text:
        score += 15
        feedback.append(f"Search references '{expected_index}'")
        subscores['targets_index'] = True
    else:
        feedback.append(f"FAIL: Search does not reference '{expected_index}'")
        subscores['targets_index'] = False

    # 4. Dashboard exists
    target_dash = None
    for d in new_dashboards:
        if d.get('normalized_name') == expected_dash_name:
            target_dash = d
            break
            
    if target_dash:
        score += 20
        feedback.append(f"Dashboard '{target_dash['name']}' exists")
        subscores['dashboard_exists'] = True
    else:
        feedback.append(f"FAIL: Dashboard '{expected_dash_name}' not found")
        subscores['dashboard_exists'] = False
        target_dash = new_dashboards[-1] if new_dashboards else {}

    # 5. Dashboard has >= 2 panels
    panel_count = target_dash.get('panel_count', 0)
    if panel_count >= 2:
        score += 15
        feedback.append(f"Dashboard has {panel_count} panels")
        subscores['dashboard_panels'] = True
    elif panel_count == 1:
        feedback.append("FAIL: Dashboard has only 1 panel, needs at least 2")
        subscores['dashboard_panels'] = False
    else:
        feedback.append("FAIL: Dashboard has no panels")
        subscores['dashboard_panels'] = False

    # 6. Dashboard references data
    xml_preview = target_dash.get('xml_preview', '').lower()
    refs_logs = any(kw in xml_preview for kw in [expected_index, expected_command, 'ssh', 'brute'])
    if refs_logs:
        score += 10
        feedback.append("Dashboard searches reference log data")
        subscores['dashboard_refs_logs'] = True
    else:
        feedback.append("FAIL: Dashboard searches do not reference relevant log data")
        subscores['dashboard_refs_logs'] = False

    passed = score >= 60 and subscores.get('saved_search_exists', False) and subscores.get('uses_transaction', False) and subscores.get('dashboard_exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "search_query": search_text,
            "panel_count": panel_count,
            "xml_preview": xml_preview[:200]
        }
    }