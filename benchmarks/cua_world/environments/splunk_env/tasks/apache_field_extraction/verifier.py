#!/usr/bin/env python3
"""
Verifier for apache_field_extraction task.

Verifies the creation of Splunk knowledge objects and tests their functionality:
1. 'error_severity' field extraction for 'apache_error' sourcetype (20 pts)
2. 'log_client_ip' field extraction for 'apache_error' sourcetype (20 pts)
3. Functional test: the error_severity extraction successfully parses logs (20 pts)
4. A saved report named 'Apache_Error_Analysis' exists (20 pts)
5. The saved report queries 'web_logs' and uses at least one extracted field (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_apache_field_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/apache_field_extraction_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    new_exts = analysis.get('new_extractions', [])
    new_srchs = analysis.get('new_searches', [])
    func_tests = analysis.get('functional_tests', {})

    score = 0
    feedback = []
    subscores = {}

    # Criterion 1: error_severity extraction exists
    err_ext = next((e for e in new_exts if 'error_severity' in e['name'].lower() and 'apache_error' in e['stanza'].lower()), None)
    if err_ext:
        score += 20
        feedback.append(f"error_severity extraction found: {err_ext['name']}")
        subscores['error_severity_exists'] = True
    else:
        feedback.append("FAIL: error_severity extraction not found for apache_error sourcetype")
        subscores['error_severity_exists'] = False

    # Criterion 2: log_client_ip extraction exists
    ip_ext = next((e for e in new_exts if 'log_client_ip' in e['name'].lower() and 'apache_error' in e['stanza'].lower()), None)
    if ip_ext:
        score += 20
        feedback.append(f"log_client_ip extraction found: {ip_ext['name']}")
        subscores['log_client_ip_exists'] = True
    else:
        feedback.append("FAIL: log_client_ip extraction not found for apache_error sourcetype")
        subscores['log_client_ip_exists'] = False

    # Criterion 3: error_severity functional test passed
    if func_tests.get('error_severity_results', 0) > 0:
        score += 20
        feedback.append("Functional check passed: error_severity extraction successfully parsed real logs")
        subscores['error_severity_functional'] = True
    else:
        feedback.append("FAIL: error_severity functional check returned no results (regex may be incorrect)")
        subscores['error_severity_functional'] = False

    # Criterion 4: Saved report exists
    report = next((s for s in new_srchs if 'apache_error_analysis' in s['name'].lower().replace(' ', '_').replace('-', '_')), None)
    if report:
        score += 20
        feedback.append(f"Saved report found: {report['name']}")
        subscores['report_exists'] = True
    else:
        feedback.append("FAIL: Saved report 'Apache_Error_Analysis' not found")
        subscores['report_exists'] = False

    # Criterion 5: Report references web_logs AND one of the extracted fields
    if report:
        q = report.get('search', '').lower()
        if 'web_logs' in q and ('error_severity' in q or 'log_client_ip' in q):
            score += 20
            feedback.append("Saved report correctly references web_logs and an extracted field")
            subscores['report_correct'] = True
        else:
            feedback.append("FAIL: Saved report query must reference 'web_logs' AND either 'error_severity' or 'log_client_ip'")
            subscores['report_correct'] = False
    else:
        subscores['report_correct'] = False

    # Strict pass condition: At least 60 points, report exists, and at least one extraction was created
    passed = (score >= 60) and subscores.get('report_exists', False) and \
             (subscores.get('error_severity_exists', False) or subscores.get('log_client_ip_exists', False))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores,
        "details": {
            "functional_test_stats": func_tests,
            "total_new_extractions": len(new_exts),
            "total_new_reports": len(new_srchs)
        }
    }