#!/usr/bin/env python3
"""
Verifier for SMTP Email Forensics Task.

Checks if the user-generated report matches the ground truth derived from the PCAP.
"""

import json
import os
import sys
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(content):
    """
    Parses 'key: value' lines from the report content.
    Returns a dictionary with normalized keys.
    """
    data = {}
    if not content:
        return data
        
    for line in content.split('\n'):
        line = line.strip()
        if not line or ':' not in line:
            continue
            
        key, val = line.split(':', 1)
        key = key.strip().lower()
        val = val.strip()
        data[key] = val
        
    return data

def normalize_email(email):
    """Normalize email for comparison (lower case, remove brackets)."""
    if not email:
        return ""
    # Remove angle brackets if present
    email = re.sub(r'[<>]', '', email)
    # Remove 'mailto:' if present
    email = re.sub(r'mailto:', '', email, flags=re.IGNORECASE)
    return email.strip().lower()

def verify_smtp_email_forensics(traj, env_info, task_info):
    """
    Verifies the smtp_report.txt against ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    max_score = 100
    feedback_parts = []
    
    file_check = result.get('file_check', {})
    ground_truth = result.get('ground_truth', {})
    content_raw = result.get('content', "")
    
    # 1. File Existence & Validity (10 pts)
    if not file_check.get('exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file not found at /home/ga/Documents/smtp_report.txt"
        }
        
    if not file_check.get('created_during_task'):
        # This is a major anti-gaming flag
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task session")
        # We'll allow it but deduct points if it looks like a stale file
        # In strictly controlled envs, this might be a fail.
    
    score += 10
    feedback_parts.append("Report file exists")
    
    # Parse the user's report
    user_data = parse_report_content(content_raw)
    
    if not user_data:
        return {
            "passed": False,
            "score": score,
            "feedback": "Report file is empty or not in 'key: value' format"
        }

    # 2. Total Packets (15 pts)
    gt_total = ground_truth.get('total_packets', '0')
    user_total = user_data.get('total_packets', '')
    if user_total == gt_total:
        score += 15
        feedback_parts.append("Total packets correct")
    else:
        feedback_parts.append(f"Total packets incorrect (Expected: {gt_total}, Got: {user_total})")

    # 3. SMTP Packets (15 pts) - Allow slight tolerance
    gt_smtp = int(ground_truth.get('smtp_packets', '0'))
    user_smtp_str = user_data.get('smtp_packets', '0')
    try:
        user_smtp = int(user_smtp_str)
        if abs(user_smtp - gt_smtp) <= 2:
            score += 15
            feedback_parts.append("SMTP packet count correct")
        else:
            feedback_parts.append(f"SMTP packet count incorrect (Expected: ~{gt_smtp}, Got: {user_smtp})")
    except ValueError:
        feedback_parts.append(f"Invalid SMTP packet count: {user_smtp_str}")

    # 4. Sender (15 pts)
    gt_sender = normalize_email(ground_truth.get('sender', ''))
    user_sender = normalize_email(user_data.get('sender', ''))
    
    # Check for substring match in case user included 'From: ' text despite instructions
    if gt_sender and (gt_sender == user_sender or gt_sender in user_sender):
        score += 15
        feedback_parts.append("Sender correct")
    else:
        feedback_parts.append(f"Sender incorrect (Expected: {gt_sender}, Got: {user_sender})")

    # 5. Recipient (15 pts)
    gt_rcpt = normalize_email(ground_truth.get('recipient', ''))
    user_rcpt = normalize_email(user_data.get('recipient', ''))
    
    if gt_rcpt and (gt_rcpt == user_rcpt or gt_rcpt in user_rcpt):
        score += 15
        feedback_parts.append("Recipient correct")
    else:
        feedback_parts.append(f"Recipient incorrect (Expected: {gt_rcpt}, Got: {user_rcpt})")

    # 6. Server IP (15 pts)
    gt_server = ground_truth.get('server_ip', '').strip()
    user_server = user_data.get('smtp_server_ip', '').strip()
    
    if gt_server and gt_server == user_server:
        score += 15
        feedback_parts.append("Server IP correct")
    else:
        feedback_parts.append(f"Server IP incorrect (Expected: {gt_server}, Got: {user_server})")

    # 7. Client IP (15 pts)
    gt_client = ground_truth.get('client_ip', '').strip()
    user_client = user_data.get('smtp_client_ip', '').strip()
    
    if gt_client and gt_client == user_client:
        score += 15
        feedback_parts.append("Client IP correct")
    else:
        feedback_parts.append(f"Client IP incorrect (Expected: {gt_client}, Got: {user_client})")

    # Pass Threshold: 70 points (File exists + 4 correct fields)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }