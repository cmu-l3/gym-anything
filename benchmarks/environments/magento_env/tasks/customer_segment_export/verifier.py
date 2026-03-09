#!/usr/bin/env python3
"""Verifier for Customer Segment Export task."""

import json
import tempfile
import os
import logging
import base64
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customer_segment_export(traj, env_info, task_info):
    """
    Verify that the agent exported the correct customer segment.
    
    Criteria:
    1. File 'wholesale_leads.csv' exists in ~/Documents (10 pts)
    2. File is a valid CSV (10 pts)
    3. File created AFTER task start (anti-gaming) (10 pts)
    4. Contains all 3 wholesale emails (15 pts each -> 45 pts)
    5. Does NOT contain retail emails (25 pts)
    
    Pass threshold: 75 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    wholesale_emails = set(metadata.get('wholesale_emails', []))
    excluded_emails = set(metadata.get('excluded_emails', []))

    # Read result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. File Existence
    if not result.get('file_exists'):
        # Check if they left it in Downloads
        dl_mtime = result.get('latest_download_mtime', 0)
        start_time = result.get('task_start_time', 0)
        if dl_mtime > start_time:
            return {
                "passed": False, 
                "score": 20, 
                "feedback": "File exported but left in Downloads. Please move it to ~/Documents/wholesale_leads.csv as requested."
            }
        return {"passed": False, "score": 0, "feedback": "Output file 'wholesale_leads.csv' not found in ~/Documents."}
    
    score += 10
    feedback_parts.append("File exists")

    # 2. Timestamp Check
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start_time', 0)
    if file_mtime > task_start:
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp predates task start")

    # 3. Parse CSV Content
    content_b64 = result.get('file_content_base64', '')
    if not content_b64:
        return {"passed": False, "score": score, "feedback": "File is empty"}

    try:
        content_str = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        # Simple check for CSV format (headers)
        if "," not in content_str and "\t" not in content_str:
            return {"passed": False, "score": score, "feedback": "File does not appear to be a CSV"}
        
        score += 10 # Valid text/csv structure
        
        # Parse emails from content
        found_emails = set()
        
        # Try proper CSV parsing first
        try:
            reader = csv.reader(io.StringIO(content_str))
            headers = next(reader, None)
            
            # Find email column index if possible, otherwise search all fields
            email_idx = -1
            if headers:
                for i, h in enumerate(headers):
                    if 'email' in h.lower():
                        email_idx = i
                        break
            
            for row in reader:
                if email_idx >= 0 and len(row) > email_idx:
                    found_emails.add(row[email_idx].strip().lower())
                else:
                    # Fallback: search row for things looking like emails
                    for field in row:
                        if '@' in field:
                            found_emails.add(field.strip().lower())
        except Exception:
            # Fallback to simple string search if CSV parsing fails strict
            for line in content_str.splitlines():
                for part in line.split(','):
                    if '@' in part:
                        found_emails.add(part.strip().strip('"').lower())

        # 4. Check Inclusion of Wholesale Emails (15 pts each -> 45 max)
        wholesale_count = 0
        for email in wholesale_emails:
            if email.lower() in found_emails:
                score += 15
                wholesale_count += 1
        
        if wholesale_count == len(wholesale_emails):
            feedback_parts.append("All wholesale customers included")
        else:
            feedback_parts.append(f"Missing {len(wholesale_emails) - wholesale_count} wholesale customers")

        # 5. Check Exclusion of Retail Emails (25 pts)
        retail_found = False
        for email in excluded_emails:
            if email.lower() in found_emails:
                retail_found = True
                break
        
        if not retail_found:
            score += 25
            feedback_parts.append("Retail customers correctly excluded")
        else:
            feedback_parts.append("Failed: Retail customers were included in the export (filtering incorrect)")

    except Exception as e:
        feedback_parts.append(f"Error parsing file: {str(e)}")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }