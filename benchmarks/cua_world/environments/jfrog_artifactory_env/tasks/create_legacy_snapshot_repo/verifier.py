#!/usr/bin/env python3
"""
Verifier for create_legacy_snapshot_repo task.

Verifies:
1. Repository 'legacy-dev-local' exists.
2. Package Type is 'maven'.
3. snapshotVersionBehavior is 'non-unique'.
4. handleSnapshots is true.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET

def verify_create_legacy_snapshot_repo(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_key = metadata.get('target_repo_key', 'legacy-dev-local')
    target_behavior = metadata.get('required_snapshot_behavior', 'non-unique')

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    repo_config = {}
    
    # Handle Data Source (Direct JSON or Fallback XML)
    if result.get('used_fallback') is True:
        # Need to parse XML system configuration
        temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/tmp/system_config.xml", temp_xml.name)
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            
            # Navigate XML: config -> localRepositories -> localRepository
            # Find the one with key = target_key
            found_node = None
            for repo in root.findall(".//localRepository"):
                key_node = repo.find("key")
                if key_node is not None and key_node.text == target_key:
                    found_node = repo
                    break
            
            if found_node:
                # Extract relevant fields to mimic JSON structure
                repo_config['key'] = target_key
                repo_config['packageType'] = found_node.find("packageType").text if found_node.find("packageType") is not None else ""
                repo_config['handleSnapshots'] = found_node.find("handleSnapshots").text if found_node.find("handleSnapshots") is not None else "false"
                repo_config['snapshotVersionBehavior'] = found_node.find("snapshotVersionBehavior").text if found_node.find("snapshotVersionBehavior") is not None else "unique"
                # Normalize booleans
                if str(repo_config['handleSnapshots']).lower() == 'true':
                    repo_config['handleSnapshots'] = True
                else:
                    repo_config['handleSnapshots'] = False
            else:
                return {"passed": False, "score": 0, "feedback": f"Repository '{target_key}' not found in system configuration."}

        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse system configuration XML: {e}"}
        finally:
            if os.path.exists(temp_xml.name):
                os.unlink(temp_xml.name)
    else:
        # Use the JSON configuration directly
        repo_config = result.get('repo_config', {})
        if not repo_config:
             return {"passed": False, "score": 0, "feedback": f"Repository '{target_key}' not found (API returned 404)."}

    # Scoring Criteria
    score = 0
    feedback_parts = []
    
    # 1. Repository Exists (Basic Check)
    if repo_config.get('key') == target_key:
        score += 30
        feedback_parts.append(f"Repository '{target_key}' created.")
    else:
        return {"passed": False, "score": 0, "feedback": f"Repository '{target_key}' does not exist."}

    # 2. Package Type (20 pts)
    pkg_type = str(repo_config.get('packageType', '')).lower()
    if pkg_type == 'maven':
        score += 20
        feedback_parts.append("Package type is Maven.")
    else:
        feedback_parts.append(f"Wrong package type: expected 'maven', got '{pkg_type}'.")

    # 3. Handle Snapshots (10 pts)
    handle_snapshots = repo_config.get('handleSnapshots')
    # API might return boolean or string depending on version
    if isinstance(handle_snapshots, str):
        handle_snapshots = handle_snapshots.lower() == 'true'
    
    if handle_snapshots:
        score += 10
        feedback_parts.append("Snapshots enabled.")
    else:
        feedback_parts.append("Snapshots NOT enabled.")

    # 4. Non-Unique Behavior (40 pts) - CRITICAL
    behavior = str(repo_config.get('snapshotVersionBehavior', '')).lower()
    if behavior == target_behavior:
        score += 40
        feedback_parts.append("Snapshot behavior set to 'non-unique'.")
    else:
        feedback_parts.append(f"Wrong snapshot behavior: expected '{target_behavior}', got '{behavior}'.")

    # Final Evaluation
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }