#!/usr/bin/env python3
"""Verifier for interactive_geo_dashboard task.

Verifies the Splunk Simple XML configuration via REST API output.
1. Checks if the specific dashboard was created.
2. Parses the XML to ensure it has interactive form inputs (Time and Dropdown/Radio).
3. Checks the SPL query within the XML for `iplocation` and `geostats`.
4. Checks that the query uses token substitution.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_interactive_geo_dashboard(traj, env_info, task_info):
    """Verify that the geospatial authentication dashboard was created correctly."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_dashboard_name', 'Geospatial_Auth_Activity')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dashboard_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    dashboard_found = analysis.get('dashboard_found', False)
    is_newly_created = analysis.get('is_newly_created', False)
    xml_content = analysis.get('dashboard_xml', '').lower()
    
    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------
    # Criterion 1: Dashboard Exists (20 pts)
    # -------------------------------------------------------------
    if dashboard_found and is_newly_created:
        score += 20
        feedback_parts.append(f"Dashboard '{expected_name}' created")
    elif dashboard_found:
        score += 10
        feedback_parts.append(f"Dashboard '{expected_name}' modified (was not newly created)")
    elif len(analysis.get('new_dashboards', [])) > 0:
        feedback_parts.append(f"FAIL: Found new dashboards but not named '{expected_name}'")
        # Proceed with partial credit checks on the incorrectly named new dashboard
    else:
        feedback_parts.append(f"FAIL: Dashboard '{expected_name}' not found and no new dashboards created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # If the XML is empty, we can't do the rest
    if not xml_content:
        feedback_parts.append("FAIL: Dashboard is empty or missing XML definition")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # -------------------------------------------------------------
    # Criterion 2: Time Input Configured (15 pts)
    # -------------------------------------------------------------
    if '<input type="time"' in xml_content or '<input type=\'time\'' in xml_content:
        score += 15
        feedback_parts.append("Time picker input found")
    else:
        feedback_parts.append("FAIL: Missing time picker input")

    # -------------------------------------------------------------
    # Criterion 3: Choice Input Configured (15 pts)
    # -------------------------------------------------------------
    choice_input_found = any(x in xml_content for x in [
        '<input type="dropdown"', '<input type=\'dropdown\'',
        '<input type="radio"', '<input type=\'radio\'',
        '<input type="multiselect"', '<input type=\'multiselect\''
    ])
    
    if choice_input_found:
        score += 15
        feedback_parts.append("Choice input (dropdown/radio) found")
    else:
        feedback_parts.append("FAIL: Missing choice input for status filtering")

    # -------------------------------------------------------------
    # Extract SPL Queries from the XML
    # -------------------------------------------------------------
    queries = re.findall(r'<query>(.*?)</query>', xml_content, re.DOTALL)
    queries += re.findall(r'<searchstring>(.*?)</searchstring>', xml_content, re.DOTALL)
    
    query_text = " ".join(queries)

    # -------------------------------------------------------------
    # Criterion 4: Query uses `iplocation` (15 pts)
    # -------------------------------------------------------------
    if 'iplocation' in query_text:
        score += 15
        feedback_parts.append("Command 'iplocation' used in search")
    else:
        feedback_parts.append("FAIL: 'iplocation' command missing from search")

    # -------------------------------------------------------------
    # Criterion 5: Query uses `geostats` (15 pts)
    # -------------------------------------------------------------
    if 'geostats' in query_text:
        score += 15
        feedback_parts.append("Command 'geostats' used in search")
    else:
        feedback_parts.append("FAIL: 'geostats' command missing from search")

    # -------------------------------------------------------------
    # Criterion 6: Query Implements Tokens (20 pts)
    # -------------------------------------------------------------
    # Looks for tokens like $status_tok$ in the query. 
    # Must ignore $time.earliest$ which is standard time picker default.
    custom_tokens = re.findall(r'\$([a-zA-Z0-9_]+)\$', query_text)
    
    # Filter out standard time tokens to ensure they linked the custom dropdown
    non_time_tokens = [t for t in custom_tokens if not t.startswith('time.') and t not in ('earliest', 'latest')]
    
    if len(non_time_tokens) > 0:
        score += 20
        feedback_parts.append(f"Custom token integration found: ${non_time_tokens[0]}$")
    else:
        feedback_parts.append("FAIL: Search query does not implement custom form tokens")

    # -------------------------------------------------------------
    # Final Evaluation
    # -------------------------------------------------------------
    pass_threshold = 65
    passed = score >= pass_threshold and dashboard_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }