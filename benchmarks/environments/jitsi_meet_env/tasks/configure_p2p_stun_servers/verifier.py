#!/usr/bin/env python3
"""
Verifier for configure_p2p_stun_servers task.
Checks if config.js contains the correct STUN servers in the P2P block.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stun_configuration(traj, env_info, task_info):
    """
    Verify that the user correctly configured custom STUN servers in config.js.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initial scoring
    score = 0
    feedback_parts = []
    
    # 1. Check if config was modified (10 pts)
    if result_data.get('config_modified', False):
        score += 10
        feedback_parts.append("Config file was modified")
    else:
        feedback_parts.append("Config file was NOT modified")

    # 2. Check if service is reachable (sanity check that config isn't broken) (10 pts)
    if result_data.get('service_reachable', False):
        score += 10
        feedback_parts.append("Service is reachable (syntax valid)")
    else:
        feedback_parts.append("Service is NOT reachable (possible syntax error)")

    # 3. Check for verification screenshot (10 pts)
    if result_data.get('agent_screenshot_exists', False):
        score += 10
        feedback_parts.append("Verification screenshot created")
    else:
        feedback_parts.append("Verification screenshot missing")

    # 4. Analyze Config Content (70 pts)
    # We need to fetch the actual config file content
    config_local_path = tempfile.NamedTemporaryFile(delete=False, suffix='.js').name
    try:
        # The export script saved a copy to /tmp/config_final.js
        copy_from_env("/tmp/config_final.js", config_local_path)
        with open(config_local_path, 'r') as f:
            config_content = f.read()
            
        # Analysis Logic
        # config.js is a JS file. We look for the p2p object and stunServers array.
        # Since parsing full JS is hard in python without libraries, we use robust regex.
        
        # Strategy:
        # 1. Isolate the 'p2p' block.
        # 2. Look for 'stunServers' inside it.
        # 3. Look for the specific URLs.

        # Regex to find p2p: { ... } block
        # Matches "p2p: {" followed by content until matching brace roughly
        # Simplified: Look for p2p section and check content in proximity
        
        # Clean content to make regex easier (remove comments)
        clean_content = re.sub(r'//.*', '', config_content)
        clean_content = re.sub(r'/\*.*?\*/', '', clean_content, flags=re.DOTALL)
        
        # Check P2P Enabled (10 pts)
        # Look for p2p: { ... enabled: true ... } or default enabled
        # We'll just check if "enabled: false" is NOT present inside p2p block, 
        # or if "enabled: true" IS present.
        # Finding the block is tricky, so we'll look for the specific lines.
        
        p2p_match = re.search(r'p2p\s*:\s*\{([^}]+)\}', clean_content, re.DOTALL)
        
        p2p_enabled = True # Default is often true, but let's check content
        p2p_block_content = ""
        
        if p2p_match:
            p2p_block_content = p2p_match.group(1)
            if "enabled: false" in p2p_block_content:
                p2p_enabled = False
            
            if p2p_enabled:
                score += 10
                feedback_parts.append("P2P is enabled")
            else:
                feedback_parts.append("P2P is disabled (incorrect)")
        else:
            # Fallback: strict block finding failed, try looser search
            if "p2p" in clean_content and "stunServers" in clean_content:
                # Assuming structure exists
                score += 10
                feedback_parts.append("P2P block structure detected")
                p2p_block_content = clean_content # Search whole file if extraction fails (risky but lenient)
            else:
                feedback_parts.append("Could not locate P2P configuration block")

        # Check STUN Servers (30 pts each)
        required_servers = [
            "stun:stun.l.google.com:19302",
            "stun:stun1.l.google.com:19302"
        ]
        
        # Check if they are in the file/block
        for server in required_servers:
            # We look for the server string enclosed in quotes
            # e.g. 'stun:stun.l.google.com:19302' or "stun:stun.l.google.com:19302"
            
            # Escape dots for regex
            server_esc = re.escape(server)
            pattern = f"['\"]{server_esc}['\"]"
            
            if re.search(pattern, p2p_block_content if p2p_match else clean_content):
                score += 30
                feedback_parts.append(f"Found server {server}")
            else:
                feedback_parts.append(f"Missing server {server}")

    except Exception as e:
        feedback_parts.append(f"Error analyzing config file: {str(e)}")
    finally:
        if os.path.exists(config_local_path):
            os.unlink(config_local_path)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }