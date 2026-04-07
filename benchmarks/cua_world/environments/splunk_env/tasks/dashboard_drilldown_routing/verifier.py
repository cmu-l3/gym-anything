#!/usr/bin/env python3
"""Verifier for dashboard_drilldown_routing task.

Verifies that the agent created two SimpleXML dashboards linked via drilldown:
1. Detailed_IP_Investigation (has token input 'target_ip' and uses it in a search)
2. Global_Threat_Overview (has drilldown passing token to detailed dashboard)

Criteria:
- Detailed Dashboard Exists (15 pts)
- Overview Dashboard Exists (15 pts)
- Token Input Defined (20 pts)
- Token Used in Search (20 pts)
- Drilldown Configured (30 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dashboard_drilldown_routing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dashboard_drilldown_routing_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    detailed_xml = analysis.get('detailed_dashboard_xml', '')
    summary_xml = analysis.get('summary_dashboard_xml', '')

    score = 0
    feedback = []
    
    # Criterion 1: Detailed dashboard exists (15 points)
    if detailed_xml:
        score += 15
        feedback.append("Detailed dashboard ('Detailed_IP_Investigation') exists")
    else:
        feedback.append("FAIL: Detailed_IP_Investigation dashboard not found")
        
    # Criterion 2: Summary dashboard exists (15 points)
    if summary_xml:
        score += 15
        feedback.append("Summary dashboard ('Global_Threat_Overview') exists")
    else:
        feedback.append("FAIL: Global_Threat_Overview dashboard not found")
        
    # Criterion 3: Detailed dashboard has token 'target_ip' input (20 points)
    if detailed_xml and re.search(r'token=[\'"]target_ip[\'"]', detailed_xml, re.IGNORECASE):
        score += 20
        feedback.append("Detailed dashboard defines token input 'target_ip'")
    elif detailed_xml:
        feedback.append("FAIL: Detailed dashboard missing token input named 'target_ip'")

    # Criterion 4: Detailed dashboard uses token in search (20 points)
    if detailed_xml and '$target_ip$' in detailed_xml:
        score += 20
        feedback.append("Detailed dashboard search successfully references '$target_ip$' token")
    elif detailed_xml:
        feedback.append("FAIL: Detailed dashboard search does not use '$target_ip$' token in queries")

    # Criterion 5: Summary dashboard has drilldown passing token (30 points)
    if summary_xml:
        # Link should target the detailed dashboard view
        has_link = 'detailed_ip_investigation' in summary_xml.lower()
        # Drilldown must pass the target_ip token (usually <param name="form.target_ip"> or similar in the URL link)
        passes_token = 'form.target_ip' in summary_xml.lower() or 'target_ip=' in summary_xml.lower()
        
        if has_link and passes_token:
            score += 30
            feedback.append("Summary dashboard has drilldown configured correctly")
        elif has_link:
            feedback.append("FAIL: Summary dashboard links to detailed dashboard but does not pass target_ip token")
        else:
            feedback.append("FAIL: Summary dashboard missing drilldown link to detailed_ip_investigation")

    # Final logic
    key_criteria_met = bool(detailed_xml) and bool(summary_xml)
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }