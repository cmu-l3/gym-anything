#!/usr/bin/env python3
"""Verifier for db_reader_patient_feed task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_db_reader_patient_feed(traj, env_info, task_info):
    """Verify that the database reader channel was created and processed records."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/db_reader_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    config = result.get('config', {})
    status = result.get('status', {})
    output = result.get('output', {})
    database = result.get('database', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Channel Creation & Basic Config (40 pts)
    if result.get('channel_exists', False):
        score += 10
        feedback_parts.append("Channel created")
        
        if config.get('source_is_db_reader'):
            score += 12
            feedback_parts.append("Source is Database Reader")
        else:
            feedback_parts.append("Source is NOT Database Reader")
            
        if config.get('dest_is_file_writer'):
            score += 10
            feedback_parts.append("Destination is File Writer")
        else:
            feedback_parts.append("Destination is NOT File Writer")
            
        if config.get('has_transformer'):
            score += 8
            feedback_parts.append("Transformer logic detected")
        else:
            feedback_parts.append("No transformer logic detected")
    else:
        feedback_parts.append("Channel not found")
        
    # 2. Detailed Configuration (18 pts)
    if config.get('jdbc_correct'):
        score += 8
        feedback_parts.append("JDBC connection correct")
    elif result.get('channel_exists', False):
        feedback_parts.append("JDBC configuration incorrect")
        
    if config.get('sql_query_correct'):
        score += 10
        feedback_parts.append("SQL query correct (references table + filter)")
    elif result.get('channel_exists', False):
        feedback_parts.append("SQL query incorrect or missing filter")
        
    # 3. Operational Status (10 pts)
    if status.get('started'):
        score += 10
        feedback_parts.append("Channel is deployed and started")
    else:
        feedback_parts.append("Channel is not started")
        
    # 4. Message Processing (12 pts)
    msgs_received = status.get('msgs_received', 0)
    if msgs_received > 0:
        score += 12
        feedback_parts.append(f"Channel processed {msgs_received} messages")
    elif database.get('processed_count', 0) > 0:
        # Fallback if API stats lag
        score += 8
        feedback_parts.append("DB records updated, implying processing occurred")
    else:
        feedback_parts.append("No messages processed")
        
    # 5. Output Verification (20 pts)
    if output.get('files_exist'):
        score += 10
        feedback_parts.append(f"Output files found ({output.get('file_count')} files)")
        
        if output.get('content_valid'):
            score += 10
            feedback_parts.append("HL7 content valid (MSH/ADT^A04/PID)")
        else:
            feedback_parts.append("HL7 content invalid (Missing MSH/PID or wrong type)")
    else:
        feedback_parts.append("No output files found")

    # Anti-gaming check: Ensure work was actually done
    initial_channel_count = result.get('initial_channel_count', 0)
    current_channel_count = result.get('current_channel_count', 0)
    
    if current_channel_count <= initial_channel_count and not result.get('channel_exists'):
         score = 0
         feedback_parts = ["Anti-gaming: No new channels created and target channel not found"]

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }