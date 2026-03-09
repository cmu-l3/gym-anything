#!/usr/bin/env python3
"""
Verifier for tcp_conversation_profiling task.

Checks:
1. Report file exists and has correct stats (Total, Longest, Highest, Avg).
2. CSV file exists and has correct row count and structure.
3. Files were created during the task (anti-gaming).
"""

import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tcp_conversation_profiling(traj, env_info, task_info):
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
    max_score = 100
    feedback_parts = []
    
    # Extract Ground Truth
    gt = result.get('ground_truth', {})
    gt_total = int(gt.get('total_conversations', 0))
    gt_avg = float(gt.get('average_duration', 0.0))
    
    # Parse complex ground truth strings (Format: ADDR_A ADDR_B VALUE)
    gt_longest_info = gt.get('longest_info', "").split()
    gt_highest_info = gt.get('highest_info', "").split()
    
    gt_longest_addrs = set(gt_longest_info[:2]) if len(gt_longest_info) >= 2 else set()
    gt_longest_val = float(gt_longest_info[2]) if len(gt_longest_info) >= 3 else 0.0
    
    gt_highest_addrs = set(gt_highest_info[:2]) if len(gt_highest_info) >= 2 else set()
    gt_highest_val = int(gt_highest_info[2]) if len(gt_highest_info) >= 3 else 0
    
    # ---------------------------------------------------------
    # CHECK 1: Text Report (50 points)
    # ---------------------------------------------------------
    report = result.get('report_file', {})
    if not report.get('exists'):
        feedback_parts.append("Report file missing")
    else:
        # Decode content
        try:
            content = base64.b64decode(report.get('content_base64', '')).decode('utf-8', errors='ignore')
        except:
            content = ""
            
        if not report.get('created_in_task'):
            feedback_parts.append("Report file not created during task")
        else:
            score += 5 # File exists and fresh
            
            # Check 1a: Total Count (10 pts)
            # Look for number after "Total TCP Conversations"
            total_match = re.search(r"Total TCP Conversations:\s*(\d+)", content, re.IGNORECASE)
            if total_match:
                user_total = int(total_match.group(1))
                if user_total == gt_total:
                    score += 10
                    feedback_parts.append("Correct total count")
                else:
                    feedback_parts.append(f"Total count mismatch (Found {user_total}, Expected {gt_total})")
            else:
                feedback_parts.append("Could not parse total count")

            # Check 1b: Longest Duration (15 pts)
            # Look for duration value
            dur_match = re.search(r"Duration:\s*([\d\.]+)\s*s?", content, re.IGNORECASE)
            # Also check if IPs are mentioned
            found_longest_ips = any(ip in content for ip in gt_longest_addrs)
            
            if dur_match:
                user_dur = float(dur_match.group(1))
                if abs(user_dur - gt_longest_val) < 1.0: # 1 sec tolerance
                    if found_longest_ips:
                        score += 15
                        feedback_parts.append("Correct longest duration & IPs")
                    else:
                        score += 10
                        feedback_parts.append("Correct longest duration value, but IPs unclear")
                else:
                    feedback_parts.append(f"Longest duration mismatch (Found {user_dur}, Expected {gt_longest_val})")
            else:
                feedback_parts.append("Could not parse longest duration")

            # Check 1c: Highest Volume (10 pts)
            bytes_match = re.search(r"Bytes:\s*(\d+)", content, re.IGNORECASE)
            found_highest_ips = any(ip in content for ip in gt_highest_addrs)
            
            if bytes_match:
                user_bytes = int(bytes_match.group(1))
                # 1% tolerance for bytes
                if abs(user_bytes - gt_highest_val) <= (gt_highest_val * 0.01):
                    if found_highest_ips:
                        score += 10
                        feedback_parts.append("Correct highest volume & IPs")
                    else:
                        score += 7
                        feedback_parts.append("Correct highest volume value")
                else:
                    feedback_parts.append(f"Volume mismatch (Found {user_bytes}, Expected {gt_highest_val})")
            else:
                feedback_parts.append("Could not parse volume bytes")

            # Check 1d: Average Duration (10 pts)
            avg_match = re.search(r"Average Duration:\s*([\d\.]+)", content, re.IGNORECASE)
            if avg_match:
                user_avg = float(avg_match.group(1))
                # 10% tolerance
                if abs(user_avg - gt_avg) <= (gt_avg * 0.1) or (gt_avg == 0 and user_avg == 0):
                    score += 10
                    feedback_parts.append("Correct average duration")
                else:
                    feedback_parts.append(f"Average duration mismatch (Found {user_avg}, Expected {gt_avg})")
            else:
                feedback_parts.append("Could not parse average duration")

    # ---------------------------------------------------------
    # CHECK 2: CSV File (40 points)
    # ---------------------------------------------------------
    csv_file = result.get('csv_file', {})
    if not csv_file.get('exists'):
        feedback_parts.append("CSV file missing")
    else:
        if not csv_file.get('created_in_task'):
            feedback_parts.append("CSV file not created during task")
        else:
            score += 10 # File exists and fresh
            
            # Check Row Count (20 pts)
            row_count = csv_file.get('row_count', 0)
            if row_count == gt_total:
                score += 20
                feedback_parts.append("CSV row count exact match")
            elif abs(row_count - gt_total) <= 2:
                score += 15
                feedback_parts.append("CSV row count close match")
            else:
                feedback_parts.append(f"CSV row count mismatch (Found {row_count}, Expected {gt_total})")
                
            # Check Header (10 pts)
            header = csv_file.get('header', '').lower()
            required_cols = ['address_a', 'bytes', 'duration']
            if all(col in header for col in required_cols):
                score += 10
                feedback_parts.append("CSV header looks correct")
            else:
                feedback_parts.append("CSV header missing required columns")

    # ---------------------------------------------------------
    # CHECK 3: App Running (10 points)
    # ---------------------------------------------------------
    if result.get('app_was_running'):
        score += 10
        feedback_parts.append("Wireshark was open")
    else:
        feedback_parts.append("Wireshark closed unexpectedly")

    # Pass Threshold
    # Needs 60 points + Report Existence + CSV Existence
    passed = (score >= 60) and report.get('exists') and csv_file.get('exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }