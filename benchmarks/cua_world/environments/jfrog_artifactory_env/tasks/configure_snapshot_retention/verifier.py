#!/usr/bin/env python3
"""
Verifier for configure_snapshot_retention task.

Verifies:
1. Repository 'project-alpha-snapshots' exists.
2. Repository type is 'maven'.
3. 'handleSnapshots' is enabled.
4. 'maxUniqueSnapshots' is set to 5.

Method:
- Parses the Artifactory system configuration XML (fetched via /api/system/configuration).
- Falls back to VLM if XML parsing fails but visual evidence is strong (optional).
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_snapshot_retention(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_key = metadata.get('target_repo_key', 'project-alpha-snapshots')
    expected_limit = metadata.get('expected_max_unique_snapshots', 5)
    
    # Setup temporary files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    try:
        # 1. Copy result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        # 2. Copy config XML
        config_path_in_env = result_data.get('config_xml_path', '/tmp/artifactory_config.xml')
        try:
            copy_from_env(config_path_in_env, temp_config.name)
            xml_content_available = True
        except Exception:
            xml_content_available = False
            
        # Evaluation Logic
        score = 0
        feedback_parts = []
        
        if not xml_content_available:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Failed to retrieve Artifactory configuration for verification."
            }

        # Parse XML
        # Structure: <config><localRepositories><localRepository><key>...</key>...</localRepository></localRepositories></config>
        repo_found = False
        repo_type_correct = False
        snapshots_handled = False
        retention_correct = False
        
        try:
            tree = ET.parse(temp_config.name)
            root = tree.getroot()
            
            # Find the specific repository
            # Namespaces might exist, but usually Artifactory config is simple or has a default namespace
            # We'll search recursively for localRepository with the matching key
            
            target_repo_node = None
            
            # Search strategy: iterate all localRepository nodes
            for repo in root.findall(".//localRepository"):
                key_node = repo.find("key")
                if key_node is not None and key_node.text == target_key:
                    target_repo_node = repo
                    break
            
            if target_repo_node is not None:
                repo_found = True
                score += 30
                feedback_parts.append(f"Repository '{target_key}' exists")
                
                # Check package type
                type_node = target_repo_node.find("type") # basic type
                # For maven, it might be stored as 'maven' in packageType or similar fields depending on version
                # In config descriptor, often <packageType>maven</packageType>
                pkg_node = target_repo_node.find("packageType")
                
                if pkg_node is not None and pkg_node.text.lower() == "maven":
                    repo_type_correct = True
                    score += 20
                    feedback_parts.append("Package type is Maven")
                else:
                    feedback_parts.append(f"Wrong package type: {pkg_node.text if pkg_node is not None else 'Unknown'}")

                # Check handle snapshots
                handle_snap_node = target_repo_node.find("handleSnapshots")
                if handle_snap_node is not None and handle_snap_node.text == "true":
                    snapshots_handled = True
                    score += 20
                    feedback_parts.append("Snapshot handling enabled")
                else:
                    feedback_parts.append("Snapshot handling NOT enabled")

                # Check max unique snapshots
                limit_node = target_repo_node.find("maxUniqueSnapshots")
                if limit_node is not None:
                    try:
                        val = int(limit_node.text)
                        if val == expected_limit:
                            retention_correct = True
                            score += 30
                            feedback_parts.append(f"Retention limit correct ({val})")
                        else:
                            feedback_parts.append(f"Retention limit incorrect (found {val}, expected {expected_limit})")
                    except ValueError:
                        feedback_parts.append("Invalid retention limit value")
                else:
                    # If the node is missing, it implies default (0/unlimited)
                    feedback_parts.append("Retention limit not set (unlimited)")

            else:
                feedback_parts.append(f"Repository '{target_key}' NOT found in configuration")

        except ET.ParseError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Failed to parse system configuration XML."
            }

        # Final Assessment
        passed = (repo_found and repo_type_correct and snapshots_handled and retention_correct)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_config.name):
            os.unlink(temp_config.name)