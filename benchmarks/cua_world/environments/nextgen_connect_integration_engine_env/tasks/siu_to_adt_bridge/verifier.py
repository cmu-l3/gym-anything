#!/usr/bin/env python3
"""Verifier for siu_to_adt_bridge task.

Occupation: IT Project Manager / Clinical Systems Integration Engineer (SOC 15-1299.09)
Scenario: Two-channel SIU-to-ADT translation bridge using Channel Writer inter-channel routing.
"""

import json
import tempfile
import os


def verify_siu_to_adt_bridge(traj, env_info, task_info):
    """Verify a two-channel SIU-to-ADT bridge was correctly built."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_siu_port = metadata.get('siu_port', '6666')
    expected_table = metadata.get('db_table', 'scheduling_preregistrations')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/siu_to_adt_bridge_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    siu_channel_exists = result.get('siu_channel_exists', False)
    siu_channel_name = result.get('siu_channel_name', '')
    siu_channel_status = result.get('siu_channel_status', '')
    siu_listen_port = result.get('siu_listen_port', '')
    siu_has_js_transformer = result.get('siu_has_js_transformer', False)
    siu_has_channel_writer = result.get('siu_has_channel_writer', False)
    adt_channel_exists = result.get('adt_channel_exists', False)
    adt_channel_name = result.get('adt_channel_name', '')
    adt_channel_status = result.get('adt_channel_status', '')
    adt_has_db_writer = result.get('adt_has_db_writer', False)
    prereg_table_exists = result.get('prereg_table_exists', False)
    prereg_row_count = result.get('prereg_row_count', 0)

    score = 0
    feedback_parts = []

    # ── Wrong-target rejection ─────────────────────────────────────────────────
    # Task requires 2 channels; if fewer than 2 new channels created, reject
    new_channels = current_count - initial_count
    if new_channels < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No channels were created. Task requires two channels: 'SIU Intake Channel' and 'ADT Pre-Registration Processor'."
        }

    if new_channels == 1 and not siu_has_channel_writer and not adt_channel_exists:
        feedback_parts.append(f"Only {new_channels} channel created; task requires 2 channels for the bridge architecture")

    # ── Criterion 1: SIU Intake Channel (20 pts) ──────────────────────────────
    if siu_channel_exists:
        score += 10
        feedback_parts.append(f"SIU Intake channel found: '{siu_channel_name}'")
        name_lower = siu_channel_name.lower()
        if 'siu' in name_lower or 'intake' in name_lower or 'schedule' in name_lower:
            score += 5
            feedback_parts.append("SIU channel name matches expected pattern")

        if siu_listen_port == expected_siu_port:
            score += 5
            feedback_parts.append(f"SIU channel listening on correct port {siu_listen_port}")
        elif siu_listen_port:
            score += 2
            feedback_parts.append(f"SIU channel on port {siu_listen_port} (expected {expected_siu_port})")
        else:
            feedback_parts.append(f"SIU channel port not detected (expected {expected_siu_port})")
    else:
        feedback_parts.append("SIU Intake channel not found in database")

    # ── Criterion 2: JS transformer in SIU channel (20 pts) ───────────────────
    if siu_has_js_transformer:
        score += 20
        feedback_parts.append("JavaScript transformer with SIU/SCH field mapping detected in SIU channel")
    else:
        feedback_parts.append("JavaScript transformer for SIU->ADT field mapping not detected in SIU channel")

    # ── Criterion 3: Channel Writer destination in SIU channel (20 pts) ────────
    if siu_has_channel_writer:
        score += 20
        feedback_parts.append("Channel Writer destination detected in SIU channel (inter-channel routing)")
    else:
        feedback_parts.append("Channel Writer destination NOT found in SIU channel - inter-channel routing not configured")

    # ── Criterion 4: ADT Pre-Registration Processor channel (15 pts) ──────────
    if adt_channel_exists:
        score += 10
        feedback_parts.append(f"ADT Processor channel found: '{adt_channel_name}'")
        name_lower = adt_channel_name.lower()
        if 'adt' in name_lower or 'prereg' in name_lower or 'pre-reg' in name_lower or 'registration' in name_lower or 'processor' in name_lower:
            score += 5
            feedback_parts.append("ADT channel name matches expected pattern")
    else:
        feedback_parts.append("ADT Pre-Registration Processor channel not found")

    # ── Criterion 5: DB Writer in ADT channel (10 pts) ────────────────────────
    if adt_has_db_writer:
        score += 10
        feedback_parts.append("Database Writer to scheduling_preregistrations detected in ADT channel")
    else:
        feedback_parts.append("Database Writer for scheduling_preregistrations not found in ADT channel")

    # ── Criterion 6: scheduling_preregistrations table (10 pts) ───────────────
    if prereg_table_exists:
        score += 10
        feedback_parts.append(f"'{expected_table}' table exists in PostgreSQL")
    else:
        feedback_parts.append(f"'{expected_table}' table not found in PostgreSQL")

    # ── Criterion 7: Both channels deployed (5 pts) ────────────────────────────
    siu_up = siu_channel_status.lower() in ['deployed', 'started', 'running']
    adt_up = adt_channel_status.lower() in ['deployed', 'started', 'running']
    if siu_up and adt_up:
        score += 5
        feedback_parts.append("Both channels are deployed and active")
    elif siu_up or adt_up:
        score += 2
        deployed_name = siu_channel_name if siu_up else adt_channel_name
        feedback_parts.append(f"Only one channel deployed: {deployed_name}")
    else:
        feedback_parts.append("Neither channel appears to be deployed")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
