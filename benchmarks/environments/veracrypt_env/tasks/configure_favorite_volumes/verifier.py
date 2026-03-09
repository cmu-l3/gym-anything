#!/usr/bin/env python3
"""
Verifier for configure_favorite_volumes task.

Verification Criteria:
1. Configuration.xml contains 3 favorite volumes matching the filenames.
2. The 'archive_cold.hc' favorite entry has the ReadOnly flag set in XML.
3. All three volumes are currently mounted.
4. The 'archive_cold.hc' volume is actually mounted Read-Only (system check).
"""

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_favorite_volumes(traj, env_info, task_info):
    """
    Verify favorites configuration and mount status.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Retrieve result JSON
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

    # Parse inputs from result
    config_content = result.get('config_content', '')
    system_mounts = result.get('system_mounts', '')
    veracrypt_list = result.get('veracrypt_list', '')

    # --- Criterion 1 & 2: Check Configuration XML (60 points) ---
    favorites_found = []
    archive_is_ro_config = False
    
    if config_content:
        try:
            root = ET.fromstring(config_content)
            # Find Favorites section
            favorites_node = root.find('Favorites')
            if favorites_node is not None:
                for vol_node in favorites_node.findall('Volume'):
                    # Check text content for path
                    vol_path = vol_node.text if vol_node.text else ""
                    filename = os.path.basename(vol_path)
                    
                    # Check attributes for ReadOnly
                    # Attributes might be 'ReadOnly' or 'MountReadOnly' depending on version
                    is_ro = False
                    if vol_node.get('ReadOnly') == '1' or vol_node.get('MountReadOnly') == '1':
                        is_ro = True
                    
                    favorites_found.append(filename)
                    
                    if 'archive_cold.hc' in filename:
                        if is_ro:
                            archive_is_ro_config = True
        except ET.ParseError:
            feedback_parts.append("Error parsing Configuration.xml")

    # Check for presence of required volumes
    required_vols = ['project_active.hc', 'reference_docs.hc', 'archive_cold.hc']
    found_count = 0
    for req in required_vols:
        if any(req in f for f in favorites_found):
            found_count += 1
            
    if found_count == 3:
        score += 30
        feedback_parts.append("All 3 volumes configured as favorites")
    else:
        feedback_parts.append(f"Found {found_count}/3 favorites in config")

    # Check RO config
    if archive_is_ro_config:
        score += 30
        feedback_parts.append("Archive configured as Read-Only in favorites")
    elif any('archive_cold.hc' in f for f in favorites_found):
        feedback_parts.append("Archive is in favorites but NOT set to Read-Only")
    else:
        feedback_parts.append("Archive volume not found in favorites")

    # --- Criterion 3: Active Mounts (20 points) ---
    # We check veracrypt_list for specific filenames being mounted
    mounted_count = 0
    archive_mount_point = None
    
    for req in required_vols:
        if req in veracrypt_list:
            mounted_count += 1
            
    # Need to extract mount point for archive to check RO status
    # veracrypt_list format example: "1: /home/ga/Volumes/archive_cold.hc /dev/mapper/veracrypt1 /media/veracrypt1"
    for line in veracrypt_list.splitlines():
        if 'archive_cold.hc' in line:
            parts = line.split()
            # Usually the last part is the mount point, or the one starting with /media or /mnt
            for part in parts:
                if part.startswith('/media') or part.startswith('/mnt') or part.startswith('/home/ga/MountPoints'):
                    archive_mount_point = part

    if mounted_count == 3:
        score += 20
        feedback_parts.append("All volumes currently mounted")
    else:
        feedback_parts.append(f"Only {mounted_count}/3 volumes mounted")

    # --- Criterion 4: System Read-Only Status (20 points) ---
    # Check 'mount' command output for the archive mount point having 'ro' flag
    is_system_ro = False
    if archive_mount_point and system_mounts:
        # Look for line containing mount point
        for line in system_mounts.splitlines():
            if archive_mount_point in line:
                # Check for (ro,...) or rw vs ro
                if 'ro,' in line or '(ro' in line:
                    is_system_ro = True
                break

    if is_system_ro:
        score += 20
        feedback_parts.append("Archive verified mounted Read-Only by system")
    elif archive_mount_point:
        feedback_parts.append("Archive mounted but system reports Read-Write")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }