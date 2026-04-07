#!/usr/bin/env python3
"""
Verifier for hook_tool_prop_attach task.

Verifies:
1. Scene file exists and was saved.
2. Video file exists and was rendered.
3. XML analysis of .tnz file to confirm Hook Tool usage (Parent Handle ID).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logger = logging.getLogger(__name__)

def verify_hook_tool_prop_attach(traj, env_info, task_info):
    """
    Verify that the user attached the sunglasses prop using a Hook.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
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

    # 2. Verify Video Output (Basic Requirement)
    if result.get("video_exists") and result.get("video_created_during_task"):
        if result.get("video_size_bytes", 0) > 50000: # > 50KB
            score += 20
            feedback_parts.append("Animation rendered successfully.")
        else:
            score += 10
            feedback_parts.append("Animation rendered but file is suspiciously small.")
    else:
        feedback_parts.append("No rendered video found.")

    # 3. Verify Scene File & Hook Usage (Core Requirement)
    scene_exists = result.get("scene_exists")
    
    if scene_exists:
        score += 10
        feedback_parts.append("Scene file saved.")
        
        # Retrieve the .tnz file to analyze XML
        temp_tnz = tempfile.NamedTemporaryFile(delete=False, suffix='.tnz')
        try:
            # The export script copies the tnz to a temp loc in the container
            copy_from_env(result.get("scene_path", "/tmp/task_artifacts/spy_run.tnz"), temp_tnz.name)
            
            # Parse XML
            tree = ET.parse(temp_tnz.name)
            root = tree.getroot()
            
            # Search for Pegbars (Columns)
            # In OpenToonz .tnz XML, the schematic connections are often in the <pegbars> section
            # Look for a pegbar that is parented to another with a specific handle
            
            hook_used = False
            parenting_found = False
            
            # OpenToonz XML structure typically has a <pegbar> for each column
            # <pegbar id="Col2">
            #   <parent handle="Col1" parentHandleId="1" ... />
            # </pegbar>
            
            pegbars = root.findall(".//pegbar")
            for pegbar in pegbars:
                parent_node = pegbar.find("parent")
                if parent_node is not None:
                    parent_handle = parent_node.get("handle")
                    parent_handle_id = parent_node.get("parentHandleId")
                    
                    # We look for a column (e.g., Col2 - sunglasses) parented to another (Col1)
                    if parent_handle and "Col" in parent_handle:
                        parenting_found = True
                        
                        # Check for Hook usage
                        # parentHandleId="0" is typically the center (default)
                        # parentHandleId="1", "2"... implies a Hook
                        if parent_handle_id and parent_handle_id.isdigit() and int(parent_handle_id) > 0:
                            hook_used = True
                            logger.info(f"Found Hook usage: Pegbar {pegbar.get('id')} -> {parent_handle} using Hook #{parent_handle_id}")
                            break
            
            if hook_used:
                score += 70
                feedback_parts.append("Correctly rigged using Hook Tool (Parent Handle found).")
            elif parenting_found:
                score += 30
                feedback_parts.append("Parenting found, but Hook Tool not used (default center used).")
            else:
                feedback_parts.append("No schematic parenting found between columns.")
                
        except ET.ParseError:
            feedback_parts.append("Failed to parse scene file (invalid XML).")
        except Exception as e:
            feedback_parts.append(f"Error analyzing scene file: {str(e)}")
        finally:
            if os.path.exists(temp_tnz.name):
                os.unlink(temp_tnz.name)
    else:
        feedback_parts.append("Scene file not found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }