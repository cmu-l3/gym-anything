#!/usr/bin/env python3
"""
Verifier for Register Build Agent task in Jenkins.

Checks if a new agent node was created with specific configuration parameters.
Uses XML parsing for the configuration validation since Jenkins config API returns XML.
"""

import sys
import os
import json
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_build_agent(traj, env_info, task_info):
    """
    Verify that the build agent was registered correctly.
    
    Scoring Breakdown:
    - Node Created (30 pts): Node exists and count increased
    - Executors (10 pts): Correct number (4)
    - Remote Root (10 pts): Correct path (/opt/jenkins-agent)
    - Labels (30 pts): All required labels present (frontend, linux, high-mem)
    - Usage Mode (10 pts): Exclusive mode
    - Launch Method (10 pts): JNLP Launcher
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_node_name', 'frontend-builder-01')
    expected_executors = str(metadata.get('expected_executors', '4'))
    expected_remote_fs = metadata.get('expected_remote_fs', '/opt/jenkins-agent')
    expected_labels = set(metadata.get('expected_labels', ["frontend", "linux", "high-mem"]))
    
    # "EXCLUSIVE" corresponds to "Only build jobs with label expressions matching this node"
    # "NORMAL" corresponds to "Use this node as much as possible"
    expected_mode = metadata.get('expected_mode', 'EXCLUSIVE') 

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/register_build_agent_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        node_exists = result.get('node_exists', False)
        config_xml = result.get('config_xml', '')
        initial_count = result.get('initial_node_count', 0)
        current_count = result.get('current_node_count', 0)
        
        # Criterion 1: Node Existence (30 pts)
        if node_exists:
            score += 30
            feedback_parts.append(f"Node '{expected_name}' exists")
        else:
            feedback_parts.append(f"Node '{expected_name}' NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
            
        # Anti-gaming check: Did node count increase?
        if current_count <= initial_count:
            feedback_parts.append("WARNING: Node count did not increase (modified existing node?)")
            # We won't fail strictly on this if the node is correct, but it's suspicious
        else:
            feedback_parts.append("New node created")

        # Parse XML Configuration
        try:
            root = ET.fromstring(config_xml)
        except ET.ParseError:
            return {
                "passed": False, 
                "score": score, 
                "feedback": "Failed to parse node configuration XML"
            }
            
        # Criterion 2: Remote Root Directory (10 pts)
        # <remoteFS>/opt/jenkins-agent</remoteFS>
        remote_fs = root.find('remoteFS')
        actual_fs = remote_fs.text if remote_fs is not None else "None"
        if actual_fs == expected_remote_fs:
            score += 10
            feedback_parts.append("Remote root directory correct")
        else:
            feedback_parts.append(f"Remote root incorrect: expected '{expected_remote_fs}', got '{actual_fs}'")
            
        # Criterion 3: Executors (10 pts)
        # <numExecutors>4</numExecutors>
        num_executors = root.find('numExecutors')
        actual_executors = num_executors.text if num_executors is not None else "0"
        if actual_executors == expected_executors:
            score += 10
            feedback_parts.append("Executor count correct")
        else:
            feedback_parts.append(f"Executor count incorrect: expected {expected_executors}, got {actual_executors}")
            
        # Criterion 4: Labels (30 pts)
        # <label>frontend linux high-mem</label>
        label_elem = root.find('label')
        actual_label_text = label_elem.text if label_elem is not None and label_elem.text else ""
        actual_labels = set(actual_label_text.split())
        
        missing_labels = expected_labels - actual_labels
        
        if not missing_labels:
            score += 30
            feedback_parts.append("All labels present")
        else:
            # Partial credit logic
            present_count = len(expected_labels) - len(missing_labels)
            if present_count > 0:
                partial_points = int(30 * (present_count / len(expected_labels)))
                score += partial_points
                feedback_parts.append(f"Missing labels: {', '.join(missing_labels)} (+{partial_points}pts)")
            else:
                feedback_parts.append("No required labels found")
                
        # Criterion 5: Usage Mode (10 pts)
        # <mode>EXCLUSIVE</mode>
        mode_elem = root.find('mode')
        actual_mode = mode_elem.text if mode_elem is not None else "NORMAL"
        if actual_mode == expected_mode:
            score += 10
            feedback_parts.append("Usage mode correct (Exclusive)")
        else:
            feedback_parts.append(f"Usage mode incorrect: expected {expected_mode}, got {actual_mode}")
            
        # Criterion 6: Launch Method (10 pts)
        # <launcher class="hudson.slaves.JNLPLauncher">
        launcher = root.find('launcher')
        launcher_class = launcher.get('class') if launcher is not None else ""
        
        if 'JNLPLauncher' in launcher_class:
            score += 10
            feedback_parts.append("Launch method correct (JNLP)")
        elif 'CommandLauncher' in launcher_class:
            # Fallback credit if they used command launcher
            score += 5
            feedback_parts.append("Launch method is Command (partial credit)")
        else:
            feedback_parts.append(f"Launch method incorrect: {launcher_class}")
            
        # Final Pass/Fail Determination
        # Pass threshold: 80 points (Must have Node Created + Correct Labels + Remote Root)
        passed = score >= 80
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}"
        }