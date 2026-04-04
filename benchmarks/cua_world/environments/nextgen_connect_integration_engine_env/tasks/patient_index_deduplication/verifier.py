#!/usr/bin/env python3
"""Verifier for patient_index_deduplication task.

Occupation: Health Information Management Specialist (SOC 11-9111.00, Medical/Health Services Managers)
Scenario: ADT demographic update channel with PostgreSQL upsert deduplication and ACK response.
"""

import json
import tempfile
import os


def verify_patient_index_deduplication(traj, env_info, task_info):
    """Verify a PMI sync channel with upsert logic and response transformer."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_port = metadata.get('listen_port', '6665')
    expected_table = metadata.get('db_table', 'patient_master_index')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/patient_index_deduplication_result.json", temp_file.name)
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
    has_js_transformer = result.get('has_js_transformer', False)
    has_pid_extraction = result.get('has_pid_extraction', False)
    has_upsert_sql = result.get('has_upsert_sql', False)
    has_db_dest = result.get('has_db_dest', False)
    has_response_transformer = result.get('has_response_transformer', False)
    pmi_table_exists = result.get('pmi_table_exists', False)
    pmi_row_count = result.get('pmi_row_count', 0)
    pmi_has_unique_mrn = result.get('pmi_has_unique_mrn', False)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    score = 0
    feedback_parts = []

    # ── Wrong-target rejection ─────────────────────────────────────────────────
    if not channel_exists and current_count <= initial_count:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No channel was created. Task requires 'Patient Master Index Sync' channel with upsert deduplication."
        }

    # ── Criterion 1: Channel exists with appropriate name (15 pts) ─────────────
    if channel_exists:
        score += 10
        feedback_parts.append(f"Channel found: '{channel_name}'")
        name_lower = channel_name.lower()
        if ('patient' in name_lower or 'pmi' in name_lower) and ('master' in name_lower or 'index' in name_lower or 'sync' in name_lower or 'dedup' in name_lower):
            score += 5
            feedback_parts.append("Channel name matches expected PMI pattern")
        else:
            feedback_parts.append(f"Channel name '{channel_name}' partially matches (expected 'Patient Master Index Sync')")
    else:
        feedback_parts.append("Channel not found by expected PMI name patterns")

    # ── Criterion 2: Correct listen port (10 pts) ──────────────────────────────
    if listen_port == expected_port:
        score += 10
        feedback_parts.append(f"Listening on correct port {listen_port}")
    elif listen_port:
        score += 3
        feedback_parts.append(f"Port {listen_port} detected (expected {expected_port})")
    else:
        feedback_parts.append(f"Port not detected (expected {expected_port})")

    # ── Criterion 3: JavaScript transformer with PID field extraction (20 pts) ─
    if has_js_transformer:
        score += 12
        feedback_parts.append("JavaScript transformer detected in channel")
    else:
        feedback_parts.append("JavaScript transformer not found in channel XML")

    if has_pid_extraction:
        score += 8
        feedback_parts.append("PID segment field extraction (mrn/name/dob) detected in transformer")
    else:
        feedback_parts.append("PID-3/PID-5/PID-7 extraction not detected in channel XML")

    # ── Criterion 4: Database Writer destination (10 pts) ─────────────────────
    if has_db_dest:
        score += 10
        feedback_parts.append("Database Writer destination detected referencing patient_master_index")
    else:
        feedback_parts.append("Database Writer destination for patient_master_index not detected")

    # ── Criterion 5: PostgreSQL UPSERT / ON CONFLICT SQL (20 pts) ─────────────
    if has_upsert_sql:
        score += 20
        feedback_parts.append("ON CONFLICT (upsert) SQL detected in database writer - correct deduplication pattern")
    else:
        feedback_parts.append("ON CONFLICT / DO UPDATE upsert SQL not found - channel may create duplicates")

    # ── Criterion 6: Response transformer for ACK (10 pts) ────────────────────
    if has_response_transformer:
        score += 10
        feedback_parts.append("Response Transformer detected (for ACK message generation)")
    else:
        feedback_parts.append("Response Transformer not found - ACK responses will not be generated")

    # ── Criterion 7: patient_master_index table with constraints (10 pts) ──────
    if pmi_table_exists:
        score += 6
        feedback_parts.append(f"'{expected_table}' table exists in PostgreSQL")
        if pmi_has_unique_mrn:
            score += 4
            feedback_parts.append("mrn column has PRIMARY KEY or UNIQUE constraint (required for ON CONFLICT)")
        else:
            feedback_parts.append("mrn column missing UNIQUE/PRIMARY KEY constraint - ON CONFLICT will not work")
    else:
        feedback_parts.append(f"'{expected_table}' table not found in PostgreSQL")

    # ── Criterion 8: Channel deployed (5 pts) ─────────────────────────────────
    status_lower = channel_status.lower() if channel_status else ''
    if status_lower in ['deployed', 'started', 'running']:
        score += 5
        feedback_parts.append(f"Channel deployed and active (status: {channel_status})")
    elif status_lower not in ['', 'unknown']:
        score += 2
        feedback_parts.append(f"Channel has status: {channel_status}")
    else:
        feedback_parts.append("Channel not deployed or status unknown")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
