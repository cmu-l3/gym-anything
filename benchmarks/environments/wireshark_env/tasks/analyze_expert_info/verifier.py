#!/usr/bin/env python3
"""
Verifier for analyze_expert_info task.

Checks:
1. Report file exists and was created during the task.
2. Report contains valid sections (Severity, Top Messages, Unique Types).
3. Severity counts match ground truth (within tolerance).
4. Top 3 messages match ground truth.
5. Unique message type count matches ground truth.
"""

import json
import tempfile
import os
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(content_text):
    """
    Parses the agent's text report to extract counts and top messages.
    Returns a dictionary of extracted values.
    """
    data = {
        "errors": None,
        "warnings": None,
        "notes": None,
        "chats": None,
        "unique": None,
        "top_messages": []
    }
    
    # Normalize newlines
    text = content_text.replace('\r\n', '\n')
    
    # Extract counts using regex (case insensitive)
    # Look for patterns like "Errors: 123" or "Errors . . . 123"
    patterns = {
        "errors": r"Errors?[\s:.]+(\d+)",
        "warnings": r"Warnings?[\s:.]+(\d+)",
        "notes": r"Notes?[\s:.]+(\d+)",
        "chats": r"Chats?[\s:.]+(\d+)",
        "unique": r"unique.*types?[\s:.]+(\d+)"
    }
    
    for key, pattern in patterns.items():
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            try:
                data[key] = int(match.group(1))
            except ValueError:
                pass

    # Extract top messages
    # Look for lines starting with "1.", "2.", "3."
    lines = text.split('\n')
    for line in lines:
        line = line.strip()
        # Match lines like "1. Window is full (count: 45)"
        if re.match(r'^\d+\.', line):
            # Remove the leading number and count info to get the core message
            # e.g., "1. This is a msg (count: 5)" -> "This is a msg"
            clean_msg = re.sub(r'^\d+\.\s*', '', line) # Remove "1. "
            clean_msg = re.sub(r'\s*\(count:?\s*\d+\).*$', '', clean_msg, flags=re.IGNORECASE) # Remove count suffix
            if clean_msg:
                data["top_messages"].append(clean_msg)

    return data

def verify_analyze_expert_info(traj, env_info, task_info):
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
    
    # 1. Check file existence and timestamp (10 pts)
    report_exists = result.get('report_exists', False)
    created_during = result.get('report_created_during_task', False)
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}
    
    if created_during:
        score += 10
        feedback_parts.append("Report created")
    else:
        feedback_parts.append("Report exists but not modified (0 pts)")

    # Decode content
    try:
        content_b64 = result.get('report_content_base64', '')
        content_text = base64.b64decode(content_b64).decode('utf-8', errors='replace')
    except Exception:
        content_text = ""

    # Check format (10 pts)
    required_sections = ["Summary by Severity", "Top 3", "Unique"]
    sections_found = sum(1 for s in required_sections if s.lower() in content_text.lower())
    if sections_found == 3:
        score += 10
        feedback_parts.append("Correct format")
    elif sections_found > 0:
        score += 5
        feedback_parts.append("Partial format")
    else:
        feedback_parts.append("Incorrect format")

    # Parse Agent Data
    agent_data = parse_report_content(content_text)
    gt_stats = result.get('ground_truth_stats', {})
    
    # Helper to score counts
    def score_count(name, agent_val, gt_val, points, tolerance_pct=0.05):
        if agent_val is None:
            return 0, f"{name}: Missing"
        
        diff = abs(agent_val - gt_val)
        tolerance = max(2, int(gt_val * tolerance_pct)) # At least +/- 2 or 5%
        
        if diff <= tolerance:
            return points, f"{name}: OK"
        else:
            return 0, f"{name}: Incorrect ({agent_val} vs {gt_val})"

    # 2. Check Severity Counts (50 pts total)
    s, f = score_count("Errors", agent_data['errors'], gt_stats.get('errors', 0), 15)
    score += s; feedback_parts.append(f)
    
    s, f = score_count("Warnings", agent_data['warnings'], gt_stats.get('warnings', 0), 15)
    score += s; feedback_parts.append(f)
    
    s, f = score_count("Notes", agent_data['notes'], gt_stats.get('notes', 0), 10)
    score += s; feedback_parts.append(f)
    
    s, f = score_count("Chats", agent_data['chats'], gt_stats.get('chats', 0), 10)
    score += s; feedback_parts.append(f)

    # 3. Check Unique Types (10 pts)
    s, f = score_count("Unique Types", agent_data['unique'], gt_stats.get('unique_types', 0), 10, tolerance_pct=0.10)
    score += s; feedback_parts.append(f)

    # 4. Check Top Messages (20 pts)
    # Decode ground truth messages
    try:
        gt_msgs_b64 = result.get('ground_truth_top_msgs_base64', '')
        gt_msgs_text = base64.b64decode(gt_msgs_b64).decode('utf-8', errors='replace')
    except:
        gt_msgs_text = ""
        
    # Example line in gt_msgs_text: "  45 Connection reset (RST)"
    # We want to match "Connection reset (RST)"
    gt_top_list = []
    for line in gt_msgs_text.strip().split('\n'):
        line = line.strip()
        # Remove leading count: "45 Msg" -> "Msg"
        clean = re.sub(r'^\d+\s+', '', line)
        if clean:
            gt_top_list.append(clean.lower())

    agent_top_list = [m.lower() for m in agent_data.get('top_messages', [])]
    
    # Check overlaps
    matches = 0
    # Check top 3
    check_limit = min(3, len(gt_top_list))
    for i in range(check_limit):
        gt_msg = gt_top_list[i]
        # Check if this GT message appears in ANY of the agent's top messages
        # Use partial matching because agent might truncate
        found = False
        for agent_msg in agent_top_list:
            # Check if one contains the other
            if gt_msg in agent_msg or agent_msg in gt_msg:
                found = True
                break
            # Also check Levenshtein or fuzzy? Simple substring usually enough for this
            # Wireshark messages are specific.
        
        if found:
            matches += 1

    top_msg_score = 0
    if matches >= 3:
        top_msg_score = 20
    elif matches == 2:
        top_msg_score = 10
    elif matches == 1:
        top_msg_score = 5
        
    score += top_msg_score
    feedback_parts.append(f"Top Messages: {matches}/3 matched")

    # Final Pass check
    passed = score >= 60 and report_exists and created_during
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }