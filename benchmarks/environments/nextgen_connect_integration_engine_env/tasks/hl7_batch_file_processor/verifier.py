#!/usr/bin/env python3
"""Verifier for hl7_batch_file_processor task.

Occupation: Healthcare IT Integration Specialist (SOC 15-1211.01, Health Informatics Specialists)
Scenario: File-polling batch HL7 processor with BHS/BTS envelope splitting and DB archiving.
"""

import json
import tempfile
import os


def verify_hl7_batch_file_processor(traj, env_info, task_info):
    """Verify a file-polling batch HL7 processor channel was correctly built."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_table = metadata.get('db_table', 'batch_processing_log')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/hl7_batch_file_processor_result.json", temp_file.name)
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
    has_file_reader = result.get('has_file_reader', False)
    has_batch_processing = result.get('has_batch_processing', False)
    has_js_preprocessor = result.get('has_js_preprocessor', False)
    has_db_writer = result.get('has_db_writer', False)
    has_archive_config = result.get('has_archive_config', False)
    file_filter_correct = result.get('file_filter_correct', False)
    batch_table_exists = result.get('batch_table_exists', False)
    batch_row_count = result.get('batch_row_count', 0)
    archive_has_files = result.get('archive_has_files', False)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    score = 0
    feedback_parts = []

    # ── Wrong-target rejection ─────────────────────────────────────────────────
    if not channel_exists and current_count <= initial_count:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No channel was created. Task requires 'Nightly HL7 Batch Processor' channel with File Reader source."
        }

    # ── Criterion 1: Channel exists with appropriate name (15 pts) ─────────────
    if channel_exists:
        score += 10
        feedback_parts.append(f"Batch processor channel found: '{channel_name}'")
        name_lower = channel_name.lower()
        if 'batch' in name_lower or ('nightly' in name_lower and 'hl7' in name_lower) or ('file' in name_lower and 'processor' in name_lower):
            score += 5
            feedback_parts.append("Channel name matches expected batch processor pattern")
        else:
            feedback_parts.append(f"Channel name '{channel_name}' does not fully match 'Nightly HL7 Batch Processor'")
    else:
        feedback_parts.append("Batch processor channel not found by expected name patterns")

    # ── Criterion 2: File Reader source (NOT TCP Listener) (25 pts) ─────────────
    # This is the primary distinguishing criterion - most will use TCP by habit
    if has_file_reader:
        score += 25
        feedback_parts.append("File Reader source connector detected (correct - NOT TCP Listener)")
        if file_filter_correct:
            feedback_parts.append("File filter configured for *.hl7 files")
    else:
        feedback_parts.append("CRITICAL: File Reader source NOT detected - channel may use TCP Listener instead of File Reader")
        # Even with wrong source type, give partial credit if channel exists
        if channel_exists:
            score += 2
            feedback_parts.append("(Channel exists but source is not a File Reader)")

    # ── Criterion 3: Batch processing / preprocessor (20 pts) ─────────────────
    if has_batch_processing:
        score += 12
        feedback_parts.append("Batch processing (processBatch=true or batchScript) configured")
    if has_js_preprocessor:
        score += 8
        feedback_parts.append("JavaScript preprocessor for batch splitting detected")
    if not has_batch_processing and not has_js_preprocessor:
        feedback_parts.append("No batch splitting configuration detected (need processBatch=true or JS preprocessor)")

    # ── Criterion 4: Database Writer destination (15 pts) ─────────────────────
    if has_db_writer:
        score += 15
        feedback_parts.append(f"Database Writer destination referencing {expected_table} detected")
    else:
        feedback_parts.append(f"Database Writer destination for {expected_table} not found")

    # ── Criterion 5: Archive/move after processing (10 pts) ───────────────────
    if has_archive_config:
        score += 8
        feedback_parts.append("File archive/move configuration detected (After Processing Action)")
    else:
        feedback_parts.append("No archive/move configuration found - processed files won't be moved")

    if archive_has_files:
        score += 2
        feedback_parts.append("Files found in archive directory - channel successfully processed and moved files")

    # ── Criterion 6: batch_processing_log table (10 pts) ──────────────────────
    if batch_table_exists:
        score += 7
        feedback_parts.append(f"'{expected_table}' table exists in PostgreSQL")
        if batch_row_count > 0:
            score += 3
            feedback_parts.append(f"Table contains {batch_row_count} processed message record(s)")
    else:
        feedback_parts.append(f"'{expected_table}' table not found in PostgreSQL")

    # ── Criterion 7: Channel deployed (5 pts) ─────────────────────────────────
    status_lower = channel_status.lower() if channel_status else ''
    if status_lower in ['deployed', 'started', 'running']:
        score += 5
        feedback_parts.append(f"Channel deployed and active (status: {channel_status})")
    elif status_lower not in ['', 'unknown']:
        score += 2
        feedback_parts.append(f"Channel status: {channel_status}")
    else:
        feedback_parts.append("Channel not deployed or status unknown")

    passed = score >= 70
    feedback = "\n".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
