#!/usr/bin/env python3
"""Verifier for http_rest_enrichment_pipeline task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_http_rest_enrichment_pipeline(traj, env_info, task_info):
    """
    Verify the HTTP REST Enrichment Pipeline.
    
    Criteria:
    1. Mock Service (Port 6666) is listening and returns correct JSON logic (20 pts)
    2. Enrichment Channel (Port 6661) is listening (20 pts)
    3. Pipeline successfully enriches data (writes file with correct Region) (40 pts)
    4. Two channels exist (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # 1. Mock Service verification
    if result.get("mock_service_status") == "listening":
        if result.get("mock_east_test") == "pass" and result.get("mock_west_test") == "pass":
            score += 20
            feedback_parts.append("Mock Service (Port 6666) functioning correctly")
        else:
            score += 10
            feedback_parts.append("Mock Service listening but logic check failed (EAST/WEST logic)")
    else:
        feedback_parts.append("Mock Service (Port 6666) not listening")

    # 2. Enrichment Channel Listening
    if result.get("enrichment_channel_status") == "listening":
        score += 20
        feedback_parts.append("Enrichment Channel (Port 6661) listening")
    else:
        feedback_parts.append("Enrichment Channel (Port 6661) not listening")

    # 3. Enrichment Logic Verification (End-to-End)
    if result.get("enrichment_file_created"):
        if result.get("enrichment_logic_test") == "pass":
            score += 40
            feedback_parts.append("Pipeline verification PASSED: Output file contains correct enriched Region")
        else:
            score += 10
            feedback_parts.append("Pipeline produced output file, but enrichment logic (Region insertion) failed verification")
    else:
        feedback_parts.append("Pipeline produced NO output files during verification test")

    # 4. Channel Count
    initial = result.get("initial_channel_count", 0)
    current = result.get("current_channel_count", 0)
    if current >= initial + 2:
        score += 20
        feedback_parts.append(f"Channel count increased by {current - initial} (Expected 2)")
    elif current >= initial + 1:
        score += 10
        feedback_parts.append(f"Channel count increased by {current - initial} (Expected 2)")
    
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }