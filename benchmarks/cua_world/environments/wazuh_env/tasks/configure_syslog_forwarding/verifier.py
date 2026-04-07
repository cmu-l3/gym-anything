#!/usr/bin/env python3
"""
Verifier for configure_syslog_forwarding task.

Criteria:
1. ossec.conf modified during task (anti-gaming).
2. Two <syslog_output> blocks present with correct attributes.
3. wazuh-csyslogd process is running.
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_syslog_forwarding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    target_configs = metadata.get('target_configs', [])
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Check if file was modified (10 points)
    if result.get('file_modified_during_task', False):
        score += 10
        feedback_parts.append("ossec.conf modified during task")
    else:
        feedback_parts.append("ossec.conf NOT modified during task")

    # 2. Check Process Status (20 points)
    if result.get('csyslogd_running', False):
        score += 20
        feedback_parts.append("wazuh-csyslogd is running")
    else:
        feedback_parts.append("wazuh-csyslogd is NOT running")

    # 3. Parse and Verify Configuration (70 points)
    config_content = result.get('config_content', '')
    
    # Pre-process content to handle XML namespaces or multiple roots if necessary
    # Just wrap in a fake root to ensure validity if it's a fragment, 
    # though ossec.conf is usually a full XML.
    try:
        # Simple hack to find syslog_output blocks without strict XML parsing failure
        # (ossec.conf can sometimes have entities that confuse standard parsers)
        syslog_blocks = re.findall(r'<syslog_output>(.*?)</syslog_output>', config_content, re.DOTALL)
        
        found_configs = []
        for block in syslog_blocks:
            server_m = re.search(r'<server>(.*?)</server>', block)
            port_m = re.search(r'<port>(.*?)</port>', block)
            format_m = re.search(r'<format>(.*?)</format>', block)
            level_m = re.search(r'<level>(.*?)</level>', block)
            
            cfg = {
                'server': server_m.group(1).strip() if server_m else None,
                'port': port_m.group(1).strip() if port_m else None,
                'format': format_m.group(1).strip() if format_m else "default", # Default assumption
                'level': level_m.group(1).strip() if level_m else None
            }
            found_configs.append(cfg)
        
        # Scoring specific configurations
        if not syslog_blocks:
            feedback_parts.append("No <syslog_output> blocks found")
        
        # Check Config 1: Splunk
        splunk_target = next((c for c in target_configs if c['server'] == '10.50.20.100'), None)
        splunk_found = False
        if splunk_target:
            for cfg in found_configs:
                if cfg['server'] == splunk_target['server']:
                    splunk_found = True
                    # Check details
                    pts = 0
                    details = []
                    if cfg['port'] == splunk_target['port']: pts += 10
                    else: details.append(f"Port mismatch ({cfg['port']})")
                    
                    if cfg['format'] == splunk_target['format']: pts += 10
                    else: details.append(f"Format mismatch ({cfg['format']})")
                    
                    if cfg['level'] == splunk_target['level']: pts += 10
                    else: details.append(f"Level mismatch ({cfg['level']})")
                    
                    score += pts + 5 # +5 for finding the server
                    if pts == 30: feedback_parts.append("Splunk output configured correctly")
                    else: feedback_parts.append(f"Splunk output partial: {', '.join(details)}")
                    break
            if not splunk_found:
                feedback_parts.append("Splunk output (10.50.20.100) NOT found")

        # Check Config 2: Graylog
        graylog_target = next((c for c in target_configs if c['server'] == '10.50.20.101'), None)
        graylog_found = False
        if graylog_target:
            for cfg in found_configs:
                if cfg['server'] == graylog_target['server']:
                    graylog_found = True
                    # Check details
                    pts = 0
                    details = []
                    if cfg['port'] == graylog_target['port']: pts += 10
                    else: details.append(f"Port mismatch ({cfg['port']})")
                    
                    # 'default' format might be implicit if tag missing, regex handled this defaults to "default"
                    if cfg['format'] == graylog_target['format']: pts += 10
                    else: details.append(f"Format mismatch ({cfg['format']})")
                    
                    if cfg['level'] == graylog_target['level']: pts += 10
                    else: details.append(f"Level mismatch ({cfg['level']})")
                    
                    score += pts + 5 # +5 for finding server
                    if pts == 30: feedback_parts.append("Graylog output configured correctly")
                    else: feedback_parts.append(f"Graylog output partial: {', '.join(details)}")
                    break
            if not graylog_found:
                feedback_parts.append("Graylog output (10.50.20.101) NOT found")

    except Exception as e:
        logger.error(f"Error parsing config: {e}")
        feedback_parts.append(f"Error validating configuration structure: {str(e)}")

    # Pass logic: Must have daemon running AND at least 60 points of config correct
    # Total max is 100: 10 (mod) + 20 (daemon) + 35 (splunk) + 35 (graylog)
    passed = (score >= 70) and result.get('csyslogd_running', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }