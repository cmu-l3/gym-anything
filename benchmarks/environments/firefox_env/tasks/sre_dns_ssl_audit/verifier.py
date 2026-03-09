#!/usr/bin/env python3
"""
Verifier for SRE DNS & SSL Audit task.
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_sre_dns_ssl_audit(traj, env_info, task_info):
    """
    Verifies the SRE audit task based on:
    1. Firefox history (tool usage)
    2. Bookmarks (evidence collection)
    3. Output JSON log (structure and data validity)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
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
    
    # ---------------------------------------------------------
    # Criterion 1: Tool Usage (20 pts)
    # ---------------------------------------------------------
    tool_visits = result.get("tool_visits", 0)
    if tool_visits >= 2:
        score += 20
        feedback_parts.append("Diagnostic tools used (20/20)")
    elif tool_visits > 0:
        score += 10
        feedback_parts.append("Diagnostic tools used partially (10/20)")
    else:
        feedback_parts.append("No diagnostic tools detected in history (0/20)")

    # ---------------------------------------------------------
    # Criterion 2: Bookmarks (20 pts)
    # ---------------------------------------------------------
    folder_exists = result.get("bookmark_folder_exists", False)
    bm_count = result.get("bookmark_count_in_folder", 0)
    
    if folder_exists:
        if bm_count >= 6:
            score += 20
            feedback_parts.append(f"'Incident 2411 Audit' folder found with {bm_count} bookmarks (20/20)")
        elif bm_count >= 3:
            score += 10
            feedback_parts.append(f"'Incident 2411 Audit' folder found but only {bm_count} bookmarks (10/20)")
        else:
            score += 5
            feedback_parts.append(f"'Incident 2411 Audit' folder empty or near empty (5/20)")
    else:
        feedback_parts.append("Bookmark folder 'Incident 2411 Audit' not found (0/20)")

    # ---------------------------------------------------------
    # Criterion 3: Log File Structure & Freshness (15 pts)
    # ---------------------------------------------------------
    file_exists = result.get("file_exists", False)
    file_fresh = result.get("file_created_during_task", False)
    content_str = result.get("file_content_str", "")
    
    log_data = {}
    valid_json = False
    
    if file_exists and file_fresh:
        try:
            log_data = json.loads(content_str)
            valid_json = True
            # Check keys
            required_domains = ["google.com", "amazon.com", "microsoft.com"]
            if all(d in log_data for d in required_domains):
                score += 15
                feedback_parts.append("Audit log exists, is fresh, and has correct keys (15/15)")
            else:
                score += 10
                feedback_parts.append("Audit log exists but missing some domains (10/15)")
        except json.JSONDecodeError:
            score += 5
            feedback_parts.append("Audit log exists but is invalid JSON (5/15)")
    elif file_exists:
        feedback_parts.append("Audit log file exists but was not created during task (0/15)")
    else:
        feedback_parts.append("Audit log file not found (0/15)")

    # ---------------------------------------------------------
    # Criterion 4: DNS Data Accuracy (15 pts)
    # ---------------------------------------------------------
    dns_score = 0
    if valid_json:
        ipv4_regex = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$")
        valid_ips = 0
        for domain in ["google.com", "amazon.com", "microsoft.com"]:
            entry = log_data.get(domain, {})
            ip = entry.get("ip_address", "").strip()
            if ip and ipv4_regex.match(ip):
                valid_ips += 1
        
        if valid_ips == 3:
            dns_score = 15
        elif valid_ips > 0:
            dns_score = 5 * valid_ips
            
    score += dns_score
    if dns_score > 0:
        feedback_parts.append(f"DNS IP data valid for {valid_ips}/3 domains ({dns_score}/15)")
    else:
        feedback_parts.append("DNS IP data missing or invalid (0/15)")

    # ---------------------------------------------------------
    # Criterion 5: SSL Data Accuracy (30 pts)
    # ---------------------------------------------------------
    ssl_score = 0
    if valid_json:
        valid_ssl = 0
        for domain in ["google.com", "amazon.com", "microsoft.com"]:
            entry = log_data.get(domain, {})
            issuer = entry.get("ssl_issuer", "").lower()
            expiry = entry.get("ssl_expiry", "")
            
            # Check Issuer
            issuer_ok = False
            if domain == "google.com" and ("google" in issuer or "gts" in issuer):
                issuer_ok = True
            elif domain == "amazon.com" and ("digicert" in issuer or "amazon" in issuer):
                issuer_ok = True
            elif domain == "microsoft.com" and ("digicert" in issuer or "microsoft" in issuer):
                issuer_ok = True
            
            # Check Expiry (Basic future check)
            date_ok = False
            try:
                # Support YYYY-MM-DD
                exp_date = datetime.strptime(expiry, "%Y-%m-%d")
                if exp_date > datetime.now():
                    date_ok = True
            except ValueError:
                # Try relaxed parsing if needed or strict enforcement
                pass
                
            if issuer_ok and date_ok:
                valid_ssl += 1
                
        if valid_ssl == 3:
            ssl_score = 30
        else:
            ssl_score = 10 * valid_ssl
            
    score += ssl_score
    if ssl_score > 0:
        feedback_parts.append(f"SSL data valid for {valid_ssl}/3 domains ({ssl_score}/30)")
    else:
        feedback_parts.append("SSL data missing or invalid (0/30)")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }