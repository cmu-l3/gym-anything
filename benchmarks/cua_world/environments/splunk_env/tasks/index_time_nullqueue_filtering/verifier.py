#!/usr/bin/env python3
"""Verifier for index_time_nullqueue_filtering task.

Checks:
1. `transforms.conf` is configured correctly (DEST_KEY=queue, FORMAT=nullQueue, REGEX contains CRON).
2. `props.conf` for `syslog` is linked to the transforms stanza.
3. Functional: Normal syslog event (UUID A) was successfully ingested.
4. Functional: CRON syslog event (UUID B) was successfully dropped (nullQueue).
5. Anti-gaming: Configuration files were modified after task start.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nullqueue_filtering(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start_time', 0)
    props_mtime = result.get('props_mtime', 0)
    transforms_mtime = result.get('transforms_mtime', 0)
    
    btool_transforms = result.get('btool_transforms', '')
    btool_props = result.get('btool_props_syslog', '')
    
    count_a = result.get('uuid_a_count', 0)
    count_b = result.get('uuid_b_count', 0)

    # ================================================================
    # Criterion 1: Parse transforms.conf
    # ================================================================
    current_block = None
    valid_transform_blocks = []
    block_props = {}
    
    for line in btool_transforms.split('\n'):
        line = line.strip()
        if not line:
            continue
        if line.startswith('[') and line.endswith(']'):
            if current_block and \
               block_props.get('DEST_KEY') == 'queue' and \
               block_props.get('FORMAT') == 'nullQueue' and \
               'CRON' in block_props.get('REGEX', ''):
                valid_transform_blocks.append(current_block)
                
            current_block = line[1:-1]
            block_props = {}
        elif '=' in line and current_block:
            key, val = line.split('=', 1)
            block_props[key.strip()] = val.strip()
            
    # Check the very last block in the file
    if current_block and \
       block_props.get('DEST_KEY') == 'queue' and \
       block_props.get('FORMAT') == 'nullQueue' and \
       'CRON' in block_props.get('REGEX', ''):
        valid_transform_blocks.append(current_block)
        
    if valid_transform_blocks:
        score += 30
        feedback_parts.append(f"Valid nullQueue transform found: {valid_transform_blocks[0]}")
    else:
        feedback_parts.append("FAIL: No valid nullQueue transform found for CRON regex")

    # ================================================================
    # Criterion 2: Parse props.conf
    # ================================================================
    syslog_links_transform = False
    if valid_transform_blocks:
        for line in btool_props.split('\n'):
            line = line.strip()
            if line.lower().startswith('transforms-'):
                val = line.split('=', 1)[1].strip()
                transforms_referenced = [t.strip() for t in val.split(',')]
                if any(t in valid_transform_blocks for t in transforms_referenced):
                    syslog_links_transform = True
                    break
                    
    if syslog_links_transform:
        score += 20
        feedback_parts.append("Props correctly linked to transform")
    else:
        feedback_parts.append("FAIL: syslog props not linked to the valid transform")
        
    # ================================================================
    # Anti-gaming: Check Modification Times
    # ================================================================
    files_modified = True
    if props_mtime < task_start or transforms_mtime < task_start:
        feedback_parts.append("WARNING: Config files appear unmodified since task start")
        files_modified = False

    # ================================================================
    # Criterion 3: Valid Ingestion (UUID A should be indexed)
    # ================================================================
    if count_a > 0:
        score += 25
        feedback_parts.append("Functional: Normal event successfully indexed")
    else:
        feedback_parts.append("FAIL: Normal event was dropped or Splunk ingestion failed")

    # ================================================================
    # Criterion 4: Filtered Ingestion (UUID B should be dropped)
    # ================================================================
    if count_b == 0 and count_a > 0:
        score += 25
        feedback_parts.append("Functional: CRON event successfully dropped")
    elif count_b > 0:
        feedback_parts.append("FAIL: CRON event was indexed (filtering failed)")
    else:
        feedback_parts.append("FAIL: CRON event was not indexed, but neither was the normal event (pipeline broken)")

    key_criteria_met = files_modified and syslog_links_transform and (count_b == 0 and count_a > 0)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "uuid_a_indexed": count_a > 0,
            "uuid_b_dropped": count_b == 0,
            "valid_transforms": valid_transform_blocks,
            "syslog_linked": syslog_links_transform,
            "files_modified_properly": files_modified
        }
    }