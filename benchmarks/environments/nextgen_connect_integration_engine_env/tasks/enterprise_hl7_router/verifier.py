#!/usr/bin/env python3
"""Verifier for enterprise_hl7_router task.

Occupation: Integration Architect / IT Project Manager (SOC 15-1299.09)
Scenario: Three-channel enterprise HL7 routing facade with database-driven rules,
          Channel Writer inter-channel routing, and dead-letter-queue fallback.
"""

import json
import tempfile
import os


def verify_enterprise_hl7_router(traj, env_info, task_info):
    """Verify a three-channel enterprise HL7 routing facade was correctly built."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_port = metadata.get('facade_port', '6668')
    expected_dlq = metadata.get('dlq_table', 'dead_letter_queue')
    expected_lab_table = metadata.get('lab_table', 'lab_results_inbox')
    expected_adt_table = metadata.get('adt_table', 'adt_events_inbox')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/enterprise_hl7_router_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    facade_exists = result.get('facade_exists', False)
    facade_name = result.get('facade_name', '')
    facade_status = result.get('facade_status', '')
    facade_port = result.get('facade_port', '')
    facade_has_js_transformer = result.get('facade_has_js_transformer', False)
    facade_channel_writer_count = result.get('facade_channel_writer_count', 0)
    facade_has_dlq_writer = result.get('facade_has_dlq_writer', False)

    lab_channel_exists = result.get('lab_channel_exists', False)
    lab_channel_name = result.get('lab_channel_name', '')
    lab_channel_status = result.get('lab_channel_status', '')
    lab_has_db_writer = result.get('lab_has_db_writer', False)

    adt_channel_exists = result.get('adt_channel_exists', False)
    adt_channel_name = result.get('adt_channel_name', '')
    adt_channel_status = result.get('adt_channel_status', '')
    adt_has_db_writer = result.get('adt_has_db_writer', False)

    routing_rules_exists = result.get('routing_rules_exists', False)
    routing_rules_count = result.get('routing_rules_count', 0)
    dlq_table_exists = result.get('dlq_table_exists', False)
    lab_inbox_exists = result.get('lab_inbox_exists', False)
    adt_inbox_exists = result.get('adt_inbox_exists', False)

    score = 0
    feedback_parts = []

    # ── Wrong-target rejection ─────────────────────────────────────────────────
    new_channels = current_count - initial_count
    if new_channels < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No channels were created. Task requires three channels: Enterprise HL7 Router, Lab Results Processor, and ADT Event Handler."
        }

    # ── Criterion 1: Enterprise Router facade channel (15 pts) ─────────────────
    if facade_exists:
        score += 8
        feedback_parts.append(f"Facade/router channel found: '{facade_name}'")
        name_lower = facade_name.lower()
        if 'enterprise' in name_lower or ('router' in name_lower and 'hl7' in name_lower) or 'facade' in name_lower:
            score += 4
            feedback_parts.append("Facade channel name matches expected pattern")

        if facade_port == expected_port:
            score += 3
            feedback_parts.append(f"Facade listening on correct port {facade_port}")
        elif facade_port:
            score += 1
            feedback_parts.append(f"Facade on port {facade_port} (expected {expected_port})")
        else:
            feedback_parts.append(f"Facade port not detected (expected {expected_port})")
    else:
        feedback_parts.append("Enterprise HL7 Router (facade) channel not found")

    # ── Criterion 2: JS transformer in facade (15 pts) ────────────────────────
    if facade_has_js_transformer:
        score += 15
        feedback_parts.append("JavaScript transformer with MSH-3/MSH-9 extraction detected in facade channel")
    else:
        feedback_parts.append("JavaScript transformer (for sendingApp/messageType extraction) not found in facade channel")

    # ── Criterion 3: Channel Writer destinations in facade (20 pts) ─────────────
    if facade_channel_writer_count >= 2:
        score += 20
        feedback_parts.append(f"Facade has {facade_channel_writer_count} Channel Writer destinations (correct for Lab + ADT routing)")
    elif facade_channel_writer_count == 1:
        score += 10
        feedback_parts.append("Facade has only 1 Channel Writer (expected 2: one for Lab, one for ADT)")
    else:
        feedback_parts.append("No Channel Writer destinations detected in facade channel")

    # ── Criterion 4: Dead Letter Queue fallback destination (10 pts) ─────────────
    if facade_has_dlq_writer:
        score += 10
        feedback_parts.append(f"Dead Letter Queue database writer destination detected in facade (references {expected_dlq})")
    else:
        feedback_parts.append(f"Dead Letter Queue DB writer not found - unmatched messages have no fallback")

    # ── Criterion 5: Lab Results Processor channel (10 pts) ───────────────────
    if lab_channel_exists:
        score += 5
        feedback_parts.append(f"Lab Results Processor channel found: '{lab_channel_name}'")
        if lab_has_db_writer:
            score += 5
            feedback_parts.append(f"Lab channel has DB writer to {expected_lab_table}")
        else:
            feedback_parts.append(f"Lab channel missing DB writer for {expected_lab_table}")
    else:
        feedback_parts.append("Lab Results Processor channel not found")

    # ── Criterion 6: ADT Event Handler channel (10 pts) ───────────────────────
    if adt_channel_exists:
        score += 5
        feedback_parts.append(f"ADT Event Handler channel found: '{adt_channel_name}'")
        if adt_has_db_writer:
            score += 5
            feedback_parts.append(f"ADT channel has DB writer to {expected_adt_table}")
        else:
            feedback_parts.append(f"ADT channel missing DB writer for {expected_adt_table}")
    else:
        feedback_parts.append("ADT Event Handler channel not found")

    # ── Criterion 7: Agent-created destination tables (10 pts) ────────────────
    # NOTE: routing_rules is pre-seeded by setup_task.sh and NOT scored here
    # (scoring pre-seeded data would give ambient credit on do-nothing runs).
    # Only the 3 tables the agent must create are scored.
    table_score = 0
    if dlq_table_exists:
        table_score += 4
        feedback_parts.append(f"'{expected_dlq}' DLQ table created by agent")
    else:
        feedback_parts.append(f"'{expected_dlq}' DLQ table not found — agent must create it")
    if lab_inbox_exists:
        table_score += 3
        feedback_parts.append(f"'{expected_lab_table}' table created by agent")
    else:
        feedback_parts.append(f"'{expected_lab_table}' table not found")
    if adt_inbox_exists:
        table_score += 3
        feedback_parts.append(f"'{expected_adt_table}' table created by agent")
    else:
        feedback_parts.append(f"'{expected_adt_table}' table not found")
    score += table_score

    # Informational only: routing_rules is pre-seeded (not scored to avoid ambient credit)
    if routing_rules_exists:
        feedback_parts.append(f"routing_rules table present with {routing_rules_count} seeded rules (setup-provided, not scored)")

    # ── Criterion 8: All channels deployed (10 pts) ────────────────────────────
    facade_up = facade_status.lower() in ['deployed', 'started', 'running']
    lab_up = lab_channel_status.lower() in ['deployed', 'started', 'running']
    adt_up = adt_channel_status.lower() in ['deployed', 'started', 'running']

    deployed_count = sum([facade_up, lab_up, adt_up])
    if deployed_count == 3:
        score += 10
        feedback_parts.append("All three channels deployed and active")
    elif deployed_count == 2:
        score += 6
        feedback_parts.append(f"2/3 channels deployed (facade:{facade_up}, lab:{lab_up}, adt:{adt_up})")
    elif deployed_count == 1:
        score += 3
        feedback_parts.append(f"Only 1/3 channels deployed")
    else:
        feedback_parts.append("No channels deployed")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
