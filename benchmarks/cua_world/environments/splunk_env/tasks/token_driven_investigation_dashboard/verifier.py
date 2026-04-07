#!/usr/bin/env python3
"""
Verifier for token_driven_investigation_dashboard task.

Verification Strategy:
1. Dashboard Exists (20 pts) - Locates the specific dashboard or gives partial credit for any newly created one.
2. Text Input Token (20 pts) - Checks SimpleXML for an `<input type="text" token="target_ip">`.
3. Dropdown Input Token (20 pts) - Checks SimpleXML for an `<input type="dropdown" token="target_index">`.
4. Panel Count (20 pts) - Verifies there are >= 2 `<panel>` elements.
5. Token Usage (20 pts) - Verifies at least 2 queries reference BOTH `$target_index$` and `$target_ip$`.

Pass threshold: 80 points AND key tokens (`target_ip`, `target_index`) must be present.
"""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_token_driven_investigation_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    tmp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp_file.name)
        with open(tmp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp_file.name):
            os.unlink(tmp_file.name)

    analysis = result.get('analysis', {})
    target_dashboard = analysis.get('target_dashboard')

    if not target_dashboard:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAIL: No new dashboard found, and 'IP_Investigation_Tool' was not created."
        }

    xml_content = target_dashboard.get('xml', '')
    dashboard_name = target_dashboard.get('name', '')

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Dashboard Exists & Name Correct (20 pts)
    # ---------------------------------------------------------
    dash_normalized = dashboard_name.lower().replace(' ', '_')
    if dash_normalized == 'ip_investigation_tool':
        score += 20
        feedback.append(f"Dashboard '{dashboard_name}' successfully created")
    else:
        score += 10
        feedback.append(f"Dashboard created but named '{dashboard_name}' instead of 'IP_Investigation_Tool'")

    # ---------------------------------------------------------
    # Parse XML robustly (Fallback to regex if ElementTree fails)
    # ---------------------------------------------------------
    panel_count = 0
    has_text_ip = False
    has_dropdown_index = False
    valid_queries = 0

    try:
        root = ET.fromstring(xml_content)
        
        # Extract inputs
        inputs = root.findall('.//input')
        for inp in inputs:
            itype = inp.get('type')
            token = inp.get('token')
            if itype == 'text' and token == 'target_ip':
                has_text_ip = True
            if itype == 'dropdown' and token == 'target_index':
                has_dropdown_index = True

        # Extract panels
        panel_count = len(root.findall('.//panel'))

        # Extract queries
        queries = root.findall('.//query')
        valid_queries = sum(1 for q in queries if q.text and '$target_index$' in q.text and '$target_ip$' in q.text)
        
        if root.tag != 'form':
            feedback.append("WARNING: Dashboard root is not <form>. Forms are required for Splunk token inputs.")

    except Exception as e:
        logger.warning(f"XML Parsing failed, falling back to regex: {e}")
        # Regex Fallbacks
        panel_count = len(re.findall(r'<panel\b', xml_content, re.IGNORECASE))
        
        has_text_ip = bool(
            re.search(r'<input\s+[^>]*type=["\']text["\'][^>]*token=["\']target_ip["\']', xml_content, re.IGNORECASE) or 
            re.search(r'<input\s+[^>]*token=["\']target_ip["\'][^>]*type=["\']text["\']', xml_content, re.IGNORECASE)
        )
        has_dropdown_index = bool(
            re.search(r'<input\s+[^>]*type=["\']dropdown["\'][^>]*token=["\']target_index["\']', xml_content, re.IGNORECASE) or 
            re.search(r'<input\s+[^>]*token=["\']target_index["\'][^>]*type=["\']dropdown["\']', xml_content, re.IGNORECASE)
        )
        
        query_texts = re.findall(r'<query>(.*?)</query>', xml_content, re.IGNORECASE | re.DOTALL)
        valid_queries = sum(1 for q in query_texts if '$target_index$' in q and '$target_ip$' in q)

    # ---------------------------------------------------------
    # Criterion 2: Text Input Token (20 pts)
    # ---------------------------------------------------------
    if has_text_ip:
        score += 20
        feedback.append("Found text input with token 'target_ip'")
    else:
        feedback.append("FAIL: Missing text input with token 'target_ip'")

    # ---------------------------------------------------------
    # Criterion 3: Dropdown Input Token (20 pts)
    # ---------------------------------------------------------
    if has_dropdown_index:
        score += 20
        feedback.append("Found dropdown input with token 'target_index'")
    else:
        feedback.append("FAIL: Missing dropdown input with token 'target_index'")

    # ---------------------------------------------------------
    # Criterion 4: Panel Count (20 pts)
    # ---------------------------------------------------------
    if panel_count >= 2:
        score += 20
        feedback.append(f"Found {panel_count} panels (>= 2 required)")
    else:
        feedback.append(f"FAIL: Found {panel_count} panels, expected at least 2")

    # ---------------------------------------------------------
    # Criterion 5: Token Usage in SPL (20 pts)
    # ---------------------------------------------------------
    if valid_queries >= 2:
        score += 20
        feedback.append(f"Found {valid_queries} queries correctly using both tokens")
    elif valid_queries == 1:
        score += 10
        feedback.append("Partial: Only 1 query uses both tokens correctly")
    else:
        feedback.append("FAIL: Panel queries do not properly reference $target_index$ and $target_ip$")

    # Pass condition: must score 80% AND successfully implement the two key inputs
    passed = score >= 80 and has_text_ip and has_dropdown_index

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "dashboard_name": dashboard_name,
            "panel_count": panel_count,
            "queries_with_tokens": valid_queries
        }
    }