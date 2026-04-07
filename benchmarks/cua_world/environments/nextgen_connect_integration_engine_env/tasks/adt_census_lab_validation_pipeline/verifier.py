#!/usr/bin/env python3
"""Verifier for adt_census_lab_validation_pipeline task.

Occupation: Senior Integration Engineer (SOC 15-1299.09)
Scenario: Three-channel clinical pipeline — ADT census management,
          lab result validation with DB-driven patient lookup,
          and critical value alerting with file output.

NOTE: This is a stub verifier. The primary verification for this task
uses the VLM checklist verifier. This stub provides basic structural
scoring as a fallback.
"""

import json
import tempfile
import os


def verify_adt_census_lab_validation_pipeline(traj, env_info, task_info):
    """Verify the three-channel ADT census + lab validation pipeline."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/adt_census_pipeline_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    score = 0
    feedback_parts = []

    # ── Early exit: no channels created ─────────────────────────────────────
    new_channels = current_count - initial_count
    if new_channels < 1:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No channels were created. Task requires three channels."
        }

    # ── Criterion 1: ADT_Census_Manager channel (5 pts) ────────────────────
    if result.get('census_channel_exists', False):
        score += 3
        feedback_parts.append(f"Census channel found: '{result.get('census_channel_name', '')}'")
        census_status = result.get('census_channel_status', '').lower()
        if census_status in ['deployed', 'started', 'running']:
            score += 2
            feedback_parts.append("Census channel is deployed")
    else:
        feedback_parts.append("ADT_Census_Manager channel not found")

    # ── Criterion 2: Lab_Results_Validator channel (5 pts) ──────────────────
    if result.get('validator_channel_exists', False):
        score += 3
        feedback_parts.append(f"Validator channel found: '{result.get('validator_channel_name', '')}'")
        validator_status = result.get('validator_channel_status', '').lower()
        if validator_status in ['deployed', 'started', 'running']:
            score += 2
            feedback_parts.append("Validator channel is deployed")
    else:
        feedback_parts.append("Lab_Results_Validator channel not found")

    # ── Criterion 3: Critical_Value_Processor channel (5 pts) ───────────────
    if result.get('processor_channel_exists', False):
        score += 3
        feedback_parts.append(f"Processor channel found: '{result.get('processor_channel_name', '')}'")
        processor_status = result.get('processor_channel_status', '').lower()
        if processor_status in ['deployed', 'started', 'running']:
            score += 2
            feedback_parts.append("Processor channel is deployed")
    else:
        feedback_parts.append("Critical_Value_Processor channel not found")

    # ── Criterion 4: Validator has JS transformer + Channel Writer (10 pts) ─
    if result.get('validator_has_js_transformer', False):
        score += 5
        feedback_parts.append("Validator has JS transformer with DB lookup logic")
    else:
        feedback_parts.append("Validator missing JS transformer for census lookup")

    if result.get('validator_has_channel_writer', False):
        score += 5
        feedback_parts.append("Validator has Channel Writer to route to processor")
    else:
        feedback_parts.append("Validator missing Channel Writer destination")

    # ── Criterion 5: Database tables exist (5 pts) ──────────────────────────
    table_score = 0
    for table_key, table_name in [
        ('census_table_exists', 'active_census'),
        ('lab_results_table_exists', 'lab_results'),
        ('critical_alerts_table_exists', 'critical_alerts'),
        ('rejected_results_table_exists', 'rejected_results'),
    ]:
        if result.get(table_key, False):
            table_score += 1
            feedback_parts.append(f"Table '{table_name}' exists")
        else:
            feedback_parts.append(f"Table '{table_name}' not found")
    # Bonus point if all 4 exist
    if table_score == 4:
        table_score += 1
    score += table_score

    # ── Criterion 6: Census pipeline — ADT processing (15 pts) ─────────────
    mrn_in_census = result.get('mrn3001_in_census', 0)
    census_status = result.get('mrn3001_census_status', '').strip()
    if mrn_in_census > 0:
        score += 8
        feedback_parts.append("MRN-3001 found in active_census table")
        if census_status.lower() == 'active':
            score += 7
            feedback_parts.append("MRN-3001 census status is 'active'")
        elif census_status:
            score += 3
            feedback_parts.append(f"MRN-3001 census status is '{census_status}' (expected 'active')")
    else:
        feedback_parts.append("MRN-3001 NOT in active_census — ADT processing failed")

    # ── Criterion 7: Lab results — accepted path (15 pts) ──────────────────
    mrn3001_lab = result.get('mrn3001_in_lab_results', 0)
    mrn9999_lab = result.get('mrn9999_in_lab_results', 0)
    if mrn3001_lab > 0:
        score += 10
        feedback_parts.append(f"MRN-3001 lab results stored ({mrn3001_lab} rows)")
    else:
        feedback_parts.append("MRN-3001 NOT in lab_results — validation/routing failed")

    if mrn9999_lab == 0:
        score += 5
        feedback_parts.append("MRN-9999 correctly excluded from lab_results")
    else:
        feedback_parts.append(f"MRN-9999 found in lab_results ({mrn9999_lab} rows) — should be rejected")

    # ── Criterion 8: Rejection path (10 pts) ────────────────────────────────
    mrn9999_rejected = result.get('mrn9999_in_rejected', 0)
    if mrn9999_rejected > 0:
        score += 10
        feedback_parts.append("MRN-9999 correctly logged in rejected_results")
    else:
        feedback_parts.append("MRN-9999 NOT in rejected_results — rejection path failed")

    # ── Criterion 9: Critical value detection (15 pts) ──────────────────────
    mrn3001_alerts = result.get('mrn3001_in_critical_alerts', 0)
    alert_file_count = result.get('alert_file_count', 0)
    alert_physician = result.get('alert_physician', '').strip()

    if mrn3001_alerts > 0:
        score += 7
        feedback_parts.append(f"MRN-3001 critical alert recorded ({mrn3001_alerts} rows)")
    else:
        feedback_parts.append("MRN-3001 NOT in critical_alerts — critical detection failed")

    if alert_file_count > 0:
        score += 4
        feedback_parts.append(f"Critical alert JSON file(s) written ({alert_file_count})")
    else:
        feedback_parts.append("No alert files in /tmp/critical_alerts/")

    if alert_physician:
        score += 4
        feedback_parts.append(f"Alert contains enriched physician: {alert_physician}")
    else:
        feedback_parts.append("Alert missing physician from census enrichment")

    # ── Criterion 10: ACK/NACK responses (15 pts) ──────────────────────────
    ack_critical = result.get('ack_oru_critical', '').strip()
    ack_unknown = result.get('ack_oru_unknown', '').strip()

    if 'MSA|AA' in ack_critical or 'MSA|CA' in ack_critical:
        score += 5
        feedback_parts.append("ACK for known patient contains MSA|AA")
        # Check for department enrichment in ACK
        alert_dept = result.get('alert_department', '').strip()
        if alert_dept and alert_dept in ack_critical:
            score += 5
            feedback_parts.append(f"ACK contains enriched department: {alert_dept}")
        else:
            feedback_parts.append("ACK missing department in MSA-6")
    elif 'MSH|' in ack_critical:
        score += 2
        feedback_parts.append("Received HL7 response for known patient but MSA|AA not found")
    else:
        feedback_parts.append("No valid HL7 ACK for known patient")

    if 'MSA|AR' in ack_unknown or 'MSA|AE' in ack_unknown or 'MSA|CR' in ack_unknown:
        score += 5
        feedback_parts.append("NACK for unknown patient contains rejection code")
    elif 'MSH|' in ack_unknown:
        score += 2
        feedback_parts.append("Received HL7 response for unknown patient but rejection code not found")
    else:
        feedback_parts.append("No valid HL7 NACK for unknown patient")

    passed = score >= 60
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
