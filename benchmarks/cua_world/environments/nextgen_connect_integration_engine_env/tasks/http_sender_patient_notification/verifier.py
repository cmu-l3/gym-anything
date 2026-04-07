#!/usr/bin/env python3
"""
Verifier for http_sender_patient_notification task.
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_http_sender_patient_notification(traj, env_info, task_info):
    """
    Verify that the HTTP Sender channel was configured and worked correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_json = metadata.get('expected_json', {})
    
    # 1. Retrieve Result JSON
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
    
    # Criteria 1: Channel Exists (10 pts)
    if result.get('channel_exists'):
        score += 10
        feedback_parts.append("Channel created")
    else:
        feedback_parts.append("Channel 'Patient_Notification_API' not found")
        return {"passed": False, "score": 0, "feedback": "Channel not found"}

    # Criteria 2: Configuration (30 pts)
    # Source Port
    if result.get('source_port') == '6661':
        score += 10
        feedback_parts.append("Source port 6661 correct")
    else:
        feedback_parts.append(f"Incorrect source port: {result.get('source_port')}")
        
    # Dest Type & URL
    if result.get('dest_type') == 'HTTP Sender':
        score += 10
        feedback_parts.append("HTTP Sender configured")
    else:
        feedback_parts.append(f"Incorrect destination type: {result.get('dest_type')}")
        
    url = result.get('dest_url', '')
    if 'webhook-server:8888' in url and 'patient-notification' in url:
        score += 10
        feedback_parts.append("Destination URL correct")
    else:
        feedback_parts.append(f"Incorrect Destination URL: {url}")

    # Criteria 3: Deployment Status (10 pts)
    state = result.get('channel_state', 'UNKNOWN')
    if state in ['STARTED', 'DEPLOYED', 'RUNNING']:
        score += 10
        feedback_parts.append("Channel is deployed/started")
    else:
        feedback_parts.append(f"Channel state is {state}")

    # Criteria 4: Webhook Receipt (20 pts)
    if result.get('webhook_received'):
        score += 20
        feedback_parts.append("Webhook received message")
    else:
        feedback_parts.append("Webhook did not receive any message")
        
    # Criteria 5: Payload Verification (30 pts)
    received_payload_str = result.get('received_payload', '{}')
    try:
        if not received_payload_str:
            raise ValueError("Empty payload")
        
        payload = json.loads(received_payload_str)
        
        fields_score = 0
        fields_total = 5 # mrn, firstName, lastName, dateOfBirth, eventType
        missed_fields = []
        
        # Check MRN
        if payload.get('mrn') == expected_json.get('mrn'):
            fields_score += 1
        else:
            missed_fields.append('mrn')
            
        # Check Names
        if payload.get('firstName') == expected_json.get('firstName'):
            fields_score += 1
        else:
            missed_fields.append('firstName')
            
        if payload.get('lastName') == expected_json.get('lastName'):
            fields_score += 1
        else:
            missed_fields.append('lastName')
            
        # Check DOB
        if payload.get('dateOfBirth') == expected_json.get('dateOfBirth'):
            fields_score += 1
        else:
            missed_fields.append('dateOfBirth')
            
        # Check Event
        if payload.get('eventType') == expected_json.get('eventType'):
            fields_score += 1
        else:
            missed_fields.append('eventType')
            
        # Scale score (max 30)
        payload_points = int((fields_score / fields_total) * 30)
        score += payload_points
        
        if fields_score == fields_total:
            feedback_parts.append("JSON payload content correct")
        else:
            feedback_parts.append(f"JSON payload incorrect/missing fields: {', '.join(missed_fields)}")
            
    except json.JSONDecodeError:
        feedback_parts.append("Received payload was not valid JSON")
    except ValueError:
        feedback_parts.append("No payload to verify")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }