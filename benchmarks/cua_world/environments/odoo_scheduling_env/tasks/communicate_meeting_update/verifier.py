#!/usr/bin/env python3
"""
Verifier for communicate_meeting_update task.

Requirements:
1. Event description updated with 3 specific agenda items.
2. New message sent via Chatter with specific text.
3. Message must be a 'comment' (Send Message), not just a notification/log.
4. Message must be created AFTER task start time.
"""

import json
import os
import sys
import logging
import datetime
import tempfile
from dateutil import parser

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def verify_communicate_meeting_update(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    metadata = task_info.get('metadata', {})
    req_agenda = metadata.get('required_agenda_items', ["Revenue Analysis", "Expense Report", "Forecasting"])
    req_msg_content = metadata.get('required_message_content', "prepare your data")
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Prerequisites
    if not result.get("event_found"):
        return {"passed": False, "score": 0, "feedback": "Target event 'Q2 Financial Review' was not found in database."}

    score = 0
    feedback = []
    task_start_ts = result.get("task_start_ts", 0)

    # 3. Verify Description (Agenda) - 40 Points
    # Description is usually HTML (e.g., "<p>Agenda:...</p>"), so we check existence of strings
    description = result.get("description", "")
    # Normalize for easier checking (remove HTML tags or just check substrings)
    # Simple substring check is usually sufficient and robust for HTML content
    
    agenda_score = 0
    missing_items = []
    
    if not description:
        description = "" # handle None
        
    for item in req_agenda:
        if item.lower() in description.lower():
            agenda_score += (40 / len(req_agenda))
        else:
            missing_items.append(item)
    
    agenda_score = round(agenda_score)
    score += agenda_score
    
    if not missing_items:
        feedback.append("Agenda items successfully added to description.")
    else:
        feedback.append(f"Missing agenda items: {', '.join(missing_items)}.")

    # 4. Verify Message (Chatter) - 60 Points
    # Criteria:
    # - Created after task start
    # - Body contains "prepare your data"
    # - Type is 'comment' (Send Message) preferred, strict check depending on rigour
    
    messages = result.get("messages", [])
    valid_message_found = False
    message_type_correct = False
    message_content_correct = False
    
    # Iterate through messages to find a match
    for msg in messages:
        # Check Timestamp
        msg_date_str = msg.get('date')
        try:
            # Odoo dates are UTC strings 'YYYY-MM-DD HH:MM:SS'
            msg_dt = parser.parse(msg_date_str)
            msg_ts = msg_dt.timestamp()
            
            # Allow small clock skew (e.g., 5 seconds) just in case, but usually not needed in same container
            if msg_ts < (task_start_ts - 5):
                continue # Old message
        except:
            continue # Parse error, skip
            
        # Check Content
        body = msg.get('body', '') or ""
        # Odoo wraps messages in <p>, so use inclusion check
        if req_msg_content.lower() in body.lower():
            message_content_correct = True
            
            # Check Type
            # 'comment' = Send Message (User created)
            # 'notification' = Log Note (System or User created log)
            # We specifically want "Send Message" which alerts users
            m_type = msg.get('message_type')
            if m_type == 'comment':
                message_type_correct = True
                valid_message_found = True
                break # Found perfect match
            else:
                # Found content but wrong type (Log Note)
                # Keep searching for a better one, but remember this partial success
                pass

    if valid_message_found:
        score += 60
        feedback.append("Notification message sent successfully via Chatter.")
    elif message_content_correct:
        # Content found but was Log Note (notification) instead of Message (comment)
        score += 30
        feedback.append("Message content found, but sent as 'Log Note' instead of 'Send Message' (attendees not notified).")
    else:
        feedback.append("No new message found with the required text.")

    # 5. Final Calculation
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }