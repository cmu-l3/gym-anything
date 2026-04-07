#!/usr/bin/env python3
"""
Verifier for create_cdb_threat_intel task.
Checks API status and file contents for correct CDB list and Rule configuration.
"""

import json
import os
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cdb_threat_intel(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_ips = metadata.get('expected_ips', {})
    required_rule_text = metadata.get('required_rule_text', 'threat intelligence')
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    task_start = result.get('task_start', 0)
    api_data = result.get('api', {})
    fs_data = result.get('fs', {})

    # =========================================================
    # Check 1: CDB List Existence & Content (40 pts)
    # =========================================================
    list_exists = False
    
    # Check API response for list existence
    affected_items = api_data.get('list_meta', {}).get('data', {}).get('affected_items', [])
    if affected_items and isinstance(affected_items, list):
        if any(item.get('filename') == 'threat-intel-blocklist' for item in affected_items):
            list_exists = True
    
    # Fallback to FS check if API failed (maybe just not loaded yet but file exists)
    if not list_exists and fs_data.get('list_exists'):
        list_exists = True
        feedback.append("List found on filesystem (API might need refresh)")

    if list_exists:
        score += 15
        feedback.append("CDB list 'threat-intel-blocklist' exists.")
        
        # Check content
        # Prefer API content, fallback to FS content
        content_str = api_data.get('list_content', '')
        if not content_str or "error" in str(api_data.get('list_content', '')):
            content_str = fs_data.get('list_content', '')
        
        # Parse content
        # Format: key:value or key
        found_ips = {}
        for line in content_str.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'): continue
            parts = line.split(':')
            ip = parts[0].strip()
            category = parts[1].strip() if len(parts) > 1 else ""
            found_ips[ip] = category
            
        # Score IPs (20 pts)
        match_count = 0
        for ip in expected_ips:
            if ip in found_ips:
                match_count += 1
        
        if match_count >= 8:
            score += 20
            feedback.append("All required IPs found in list.")
        elif match_count >= 6:
            score += 15
            feedback.append(f"Found {match_count}/8 IPs (partial credit).")
        elif match_count > 0:
            score += 5
            feedback.append(f"Found {match_count}/8 IPs (minimal credit).")
        else:
            feedback.append("No required IPs found in list.")

        # Score Categories (5 pts)
        cat_match_count = 0
        for ip, expected_cat in expected_ips.items():
            if ip in found_ips and found_ips[ip] == expected_cat:
                cat_match_count += 1
        
        if cat_match_count >= 6:
            score += 5
            feedback.append("IP categories are correct.")
        else:
            feedback.append(f"IP categories mismatch or missing ({cat_match_count}/8 correct).")

    else:
        feedback.append("CDB list 'threat-intel-blocklist' NOT found.")

    # =========================================================
    # Check 2: Rule Configuration (50 pts)
    # =========================================================
    rule_found = False
    rule_data = None
    
    # Check via API
    api_rules = api_data.get('rule_def', {}).get('data', {}).get('affected_items', [])
    if api_rules:
        rule_data = api_rules[0]
        rule_found = True
    
    # Fallback/Cross-check via FS
    fs_rule_content = fs_data.get('rules_content', '')
    if 'id="100100"' in fs_rule_content or "id='100100'" in fs_rule_content:
        if not rule_found:
            feedback.append("Rule found in file but not in API (manager restart needed?).")
            # We can try to parse XML manually if API fail, but let's penalize slightly or rely on XML check
    
    if rule_found:
        score += 15
        feedback.append("Rule 100100 exists.")
        
        # Level check (10 pts)
        level = rule_data.get('level')
        if level == 12:
            score += 10
            feedback.append("Rule level is 12.")
        else:
            feedback.append(f"Rule level is {level}, expected 12.")
            
        # Group check (5 pts)
        groups = rule_data.get('groups', [])
        if 'threat_intelligence' in groups:
            score += 5
            feedback.append("Rule group correct.")
        else:
            feedback.append("Rule missing 'threat_intelligence' group.")
            
        # Description check (5 pts)
        desc = rule_data.get('description', '').lower()
        if required_rule_text.lower() in desc:
            score += 5
            feedback.append("Rule description correct.")
        else:
            feedback.append("Rule description missing required text.")
            
        # CDB Reference Check (15 pts)
        # This is hard to check via 'affected_items' detail sometimes, depending on API verbosity
        # We'll check the FS content for the specific XML tag to be sure
        # <list field="srcip" lookup="address_match">etc/lists/threat-intel-blocklist</list>
        
        # Normalize spaces for regex check
        normalized_xml = re.sub(r'\s+', ' ', fs_rule_content)
        cdb_pattern = r'<list\s+field=[\'"]srcip[\'"]\s+lookup=[\'"]address_match[\'"]>etc/lists/threat-intel-blocklist</list>'
        
        if re.search(cdb_pattern, normalized_xml):
            score += 15
            feedback.append("Rule correctly references CDB list.")
        else:
            # Try looser check
            if "etc/lists/threat-intel-blocklist" in fs_rule_content and "lookup" in fs_rule_content:
                score += 10
                feedback.append("Rule references list (format checking loose).")
            else:
                feedback.append("Rule does not appear to reference the CDB list correctly.")

    else:
        feedback.append("Rule 100100 NOT found in API.")

    # =========================================================
    # Check 3: System Status (10 pts)
    # =========================================================
    # Did they restart?
    # Check fs mtimes vs task start
    list_mtime = fs_data.get('list_mtime', 0)
    rules_mtime = fs_data.get('rules_mtime', 0)
    
    modified_during_task = (list_mtime > task_start) or (rules_mtime > task_start)
    
    # Manager status
    # API status should be "active" or "running"
    # Actually checking api_manager_status structure
    # data -> affected_items -> [0] -> status
    manager_items = api_data.get('manager_status', {}).get('data', {}).get('affected_items', [])
    manager_running = False
    if manager_items:
        status = manager_items[0].get('status', '')
        if status == 'active':
            manager_running = True
            
    if manager_running and modified_during_task:
        score += 10
        feedback.append("Manager is active and files were modified.")
    elif modified_during_task:
        feedback.append("Files modified but manager not active (restart failed?).")
    else:
        feedback.append("Manager active but files not modified during task (anti-gaming check).")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }