#!/usr/bin/env python3
"""Verifier for lab_critical_value_router task.

Occupation: Health Informatics Specialist (SOC 15-1211.01)
Scenario: Multi-destination HL7 channel routing lab results by critical value severity.
"""

import json
import tempfile
import os


def verify_lab_critical_value_router(traj, env_info, task_info):
    """Verify a multi-destination lab result routing channel was correctly configured."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_port = metadata.get('listen_port', '6664')
    critical_table = metadata.get('critical_table', 'critical_lab_results')
    normal_table = metadata.get('normal_table', 'normal_lab_results')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/lab_critical_value_router_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    channel_exists = result.get('channel_exists', False)
    channel_name = result.get('channel_name', '')
    channel_status = result.get('channel_status', '')
    listen_port = result.get('listen_port', '')
    destination_count = result.get('destination_count', 0)
    has_js_transformer = result.get('has_js_transformer', False)
    has_critical_filter = result.get('has_critical_filter', False)
    has_normal_filter = result.get('has_normal_filter', False)
    has_file_writer = result.get('has_file_writer', False)
    has_db_writer_critical = result.get('has_db_writer_critical', False)
    has_db_writer_normal = result.get('has_db_writer_normal', False)
    critical_table_exists = result.get('critical_table_exists', False)
    normal_table_exists = result.get('normal_table_exists', False)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    score = 0
    feedback_parts = []

    # ── Wrong-target rejection ─────────────────────────────────────────────────
    # If no new channel was created at all, score=0 immediately
    if not channel_exists and current_count <= initial_count:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No channel was created. The task requires creating the 'Lab Critical Value Router' channel."
        }

    # ── Criterion 1: Channel exists with appropriate name (15 pts) ─────────────
    if channel_exists:
        score += 10
        feedback_parts.append(f"Channel found in database: '{channel_name}'")
        name_lower = channel_name.lower()
        if ('lab' in name_lower or 'critical' in name_lower) and ('router' in name_lower or 'value' in name_lower or 'route' in name_lower):
            score += 5
            feedback_parts.append("Channel name matches expected pattern")
        else:
            feedback_parts.append(f"Channel name '{channel_name}' does not fully match 'Lab Critical Value Router'")
    else:
        feedback_parts.append("Channel not found in database by expected name patterns")

    # ── Criterion 2: Correct listen port (10 pts) ──────────────────────────────
    if listen_port == expected_port:
        score += 10
        feedback_parts.append(f"Listening on correct port {listen_port}")
    elif listen_port:
        score += 3
        feedback_parts.append(f"Listening on port {listen_port} (expected {expected_port})")
    else:
        feedback_parts.append(f"Port not detected (expected {expected_port})")

    # ── Criterion 3: JavaScript transformer with OBX analysis (20 pts) ─────────
    if has_js_transformer:
        score += 20
        feedback_parts.append("JavaScript transformer with OBX/abnormal flag analysis detected")
    else:
        feedback_parts.append("JavaScript transformer referencing OBX-8 not found in channel XML")

    # ── Criterion 4: Multi-destination architecture (15 pts) ──────────────────
    if destination_count >= 3:
        score += 15
        feedback_parts.append(f"Channel has {destination_count} destinations (required: 3)")
    elif destination_count == 2:
        score += 8
        feedback_parts.append(f"Channel has {destination_count} destinations (expected 3: critical DB, normal DB, audit file)")
    elif destination_count == 1:
        score += 3
        feedback_parts.append(f"Channel has only {destination_count} destination (expected 3)")
    else:
        feedback_parts.append("No destinations detected in channel configuration")

    # ── Criterion 5: Routing filter logic (10 pts) ─────────────────────────────
    filter_score = 0
    if has_critical_filter:
        filter_score += 5
        feedback_parts.append("Critical value filter logic detected")
    if has_normal_filter:
        filter_score += 5
        feedback_parts.append("Normal value filter logic detected")
    if filter_score == 0:
        feedback_parts.append("No conditional routing filter scripts detected")
    score += filter_score

    # ── Criterion 6: Specific destination types (15 pts) ──────────────────────
    dest_score = 0
    if has_db_writer_critical:
        dest_score += 5
        feedback_parts.append(f"critical_lab_results DB writer destination detected")
    else:
        feedback_parts.append("critical_lab_results DB destination not found in channel XML")

    if has_db_writer_normal:
        dest_score += 5
        feedback_parts.append(f"normal_lab_results DB writer destination detected")
    else:
        feedback_parts.append("normal_lab_results DB destination not found in channel XML")

    if has_file_writer:
        dest_score += 5
        feedback_parts.append("Audit File Writer destination detected")
    else:
        feedback_parts.append("File Writer audit destination not detected")
    score += dest_score

    # ── Criterion 7: Database tables created (10 pts) ─────────────────────────
    table_score = 0
    if critical_table_exists:
        table_score += 5
        feedback_parts.append(f"'{critical_table}' table exists in PostgreSQL")
    else:
        feedback_parts.append(f"'{critical_table}' table not found in PostgreSQL")

    if normal_table_exists:
        table_score += 5
        feedback_parts.append(f"'{normal_table}' table exists in PostgreSQL")
    else:
        feedback_parts.append(f"'{normal_table}' table not found in PostgreSQL")
    score += table_score

    # ── Criterion 8: Channel deployed (5 pts) ─────────────────────────────────
    status_lower = channel_status.lower() if channel_status else ''
    if status_lower in ['deployed', 'started', 'running']:
        score += 5
        feedback_parts.append(f"Channel is deployed and active (status: {channel_status})")
    elif status_lower not in ['', 'unknown']:
        score += 2
        feedback_parts.append(f"Channel has status: {channel_status}")
    else:
        feedback_parts.append("Channel deployment status unknown or not deployed")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
