#!/usr/bin/env python3
"""
Verifier for export_disaster_recovery_config task.
Verifies that the agent correctly exported system configuration to JSON.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_disaster_recovery_config(traj, env_info, task_info):
    """
    Verify the disaster recovery export task.
    
    Criteria:
    1. Output file exists and is valid JSON (10 pts)
    2. Metadata section is present and correct (8 pts)
    3. Major sections (Servers, Devices, Users, Layouts, Rules) match Ground Truth counts (50 pts)
    4. Anti-gaming: No passwords in export (3 pts)
    5. Anti-gaming: File created during task (5 pts)
    6. System Info and Settings correct (15 pts)
    7. Device names match ground truth (9 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    result_metadata = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            with open(tf.name, 'r') as f:
                result_metadata = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
        finally:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    # Check basic file existence
    if not result_metadata.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found at ~/dr_export/disaster_recovery_config.json"}

    # Load Agent's Exported JSON
    agent_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
        try:
            copy_from_env(result_metadata["output_path"], tf.name)
            with open(tf.name, 'r') as f:
                agent_data = json.load(f)
        except json.JSONDecodeError:
            return {"passed": False, "score": 10, "feedback": "Output file exists but is NOT valid JSON"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output file: {e}"}
        finally:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    # Load Ground Truth JSON
    ground_truth = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tf:
        try:
            copy_from_env(result_metadata["ground_truth_path"], tf.name)
            with open(tf.name, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            # If ground truth generation failed, we can't fully verify, but shouldn't fail the agent if they did well.
            # We'll use soft checks.
            logger.error(f"Failed to load ground truth: {e}")
            ground_truth = {}
        finally:
            if os.path.exists(tf.name):
                os.unlink(tf.name)

    score = 0
    feedback = []

    # 1. JSON Validity (Already checked implies +10)
    score += 10
    feedback.append("File is valid JSON")

    # 2. Metadata Section (8 pts)
    meta = agent_data.get("metadata", {})
    if meta and "exportTimestamp" in meta and "systemName" in meta:
        score += 8
        feedback.append("Metadata section valid")
    else:
        feedback.append("Missing or incomplete 'metadata' section")

    # 3. Counts Verification vs Ground Truth (50 pts total)
    # Sections: servers, devices, users, layouts, eventRules
    sections = ["servers", "devices", "users", "layouts", "eventRules"]
    
    for sec in sections:
        agent_list = agent_data.get(sec, [])
        if not isinstance(agent_list, list):
            agent_list = [] # unexpected format
            
        gt_list = ground_truth.get(sec, [])
        
        # Determine strictness: precise match preferred, but allow superset if agent found more data?
        # Usually exact match is expected for a snapshot.
        if len(agent_list) == len(gt_list) and len(gt_list) > 0:
            score += 10
            feedback.append(f"{sec}: Count matches ({len(gt_list)})")
        elif len(agent_list) > 0 and len(gt_list) == 0:
             # Ground truth failed but agent found data? Give partial.
             score += 5
             feedback.append(f"{sec}: Agent found {len(agent_list)} items (GT missing)")
        elif len(agent_list) > 0:
            # Partial credit for finding some data even if count mismatch
            score += 5
            feedback.append(f"{sec}: Count mismatch (Agent: {len(agent_list)}, Expected: {len(gt_list)})")
        else:
            feedback.append(f"{sec}: Section empty or missing")

    # 4. Anti-gaming: Password check (3 pts)
    # Check first few users for 'password', 'digest', 'hash' fields that are not empty
    password_leaked = False
    users = agent_data.get("users", [])
    for u in users:
        if isinstance(u, dict):
            if u.get("password") or u.get("digest") or u.get("hash"):
                password_leaked = True
                break
    
    if not password_leaked:
        score += 3
    else:
        feedback.append("Security Warning: User passwords included in export")

    # 5. Anti-gaming: Timestamp (5 pts)
    if result_metadata.get("file_created_during_task", False):
        score += 5
    else:
        feedback.append("File not created during task window")

    # 6. System Info and Settings (15 pts)
    sys_info = agent_data.get("systemInfo", {})
    gt_info = ground_truth.get("systemInfo", {})
    
    if sys_info.get("localSystemId") == gt_info.get("localSystemId") and sys_info.get("localSystemId"):
        score += 10
        feedback.append("System Info matches")
    elif sys_info:
        score += 5
        feedback.append("System Info present but ID mismatch")
    
    if agent_data.get("systemSettings"):
        score += 5
        feedback.append("System Settings present")

    # 7. Device Name Matching (9 pts)
    # Verify that the device names in the export match the real camera names
    gt_device_names = set(d.get("name", "") for d in ground_truth.get("devices", []))
    agent_device_names = set(d.get("name", "") for d in agent_data.get("devices", []))
    
    if gt_device_names and agent_device_names:
        common = gt_device_names.intersection(agent_device_names)
        if len(common) == len(gt_device_names):
            score += 9
            feedback.append("All device names verified")
        elif len(common) > 0:
            score += 4
            feedback.append(f"Partial device name match ({len(common)}/{len(gt_device_names)})")
    
    # Calculate Final
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }