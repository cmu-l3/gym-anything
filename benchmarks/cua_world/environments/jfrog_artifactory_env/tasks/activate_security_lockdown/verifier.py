#!/usr/bin/env python3
"""
Verifier for activate_security_lockdown task.

Checks three conditions via Artifactory System Configuration XML:
1. Offline Mode is enabled (<offlineMode>true</offlineMode>)
2. Anonymous Access is disabled (<anonAccessEnabled>false</anonAccessEnabled>)
3. System Message matches text (<systemMessage>...</systemMessage>)

Also performs a functional check that anonymous API requests return 401/404.
"""

import json
import os
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_activate_security_lockdown(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_message = metadata.get('target_message', "SECURITY ALERT: System in Offline Lockdown")
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Copy config XML
    config_xml_path = result.get('config_xml_path')
    config_exists = result.get('config_exists', False)
    
    xml_content = ""
    if config_exists and config_xml_path:
        temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(config_xml_path, temp_xml.name)
            with open(temp_xml.name, 'r') as f:
                xml_content = f.read()
        except Exception as e:
            logger.error(f"Failed to copy XML config: {e}")
        finally:
            if os.path.exists(temp_xml.name):
                os.unlink(temp_xml.name)

    score = 0
    feedback_parts = []
    
    # Parse XML
    offline_mode_set = False
    anon_access_disabled = False
    message_set = False
    
    if xml_content:
        try:
            # Artifactory config XML structure is typically:
            # <config>
            #   <offlineMode>true</offlineMode>
            #   <security>
            #       <anonAccessEnabled>false</anonAccessEnabled>
            #   </security>
            #   <serverName>...</serverName>
            #   ...
            # </config>
            # Note: The system message might be stored in <systemMessage> or similar. 
            # In some versions, it's <footerMessage> or <loginMessage>. 
            # We will search broadly or look for the text in the raw XML if structure varies.
            
            root = ET.fromstring(xml_content)
            
            # Check Offline Mode
            offline_node = root.find('.//offlineMode')
            if offline_node is not None and offline_node.text.lower() == 'true':
                offline_mode_set = True
                score += 35
                feedback_parts.append("Offline Mode ENABLED")
            else:
                feedback_parts.append("Offline Mode NOT enabled")

            # Check Anonymous Access
            # Usually under <security><anonAccessEnabled>
            anon_node = root.find('.//anonAccessEnabled')
            if anon_node is not None and anon_node.text.lower() == 'false':
                anon_access_disabled = True
                score += 35
                feedback_parts.append("Anonymous Access DISABLED")
            else:
                feedback_parts.append("Anonymous Access NOT disabled")

            # Check System Message
            # The message is specific. We can check if the XML string contains it 
            # to be robust against XML structure variations for messages.
            if target_message in xml_content:
                message_set = True
                score += 20
                feedback_parts.append("System Message SET correctly")
            else:
                feedback_parts.append(f"System Message NOT found (expected '{target_message}')")

        except ET.ParseError:
            feedback_parts.append("Failed to parse system configuration XML")
    else:
        feedback_parts.append("System configuration could not be retrieved")

    # Functional Check: Anonymous Request (10 points)
    anon_code = str(result.get('anon_http_code', '200'))
    # 401 Unauthorized or 404 (if ping disabled) or 403 Forbidden is good. 
    # 200 OK means anon access is still working.
    if anon_code in ['401', '403', '404']:
        score += 10
        feedback_parts.append(f"Anonymous API access blocked (HTTP {anon_code})")
    else:
        feedback_parts.append(f"Anonymous API access still active (HTTP {anon_code})")

    # Calculate final status
    # Must have at least Offline Mode and Anon Access correct to pass
    passed = (score >= 70) and offline_mode_set and anon_access_disabled

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }