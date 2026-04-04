#!/usr/bin/env python3
"""
Verifier for export_repo_content task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_repo_content(traj, env_info, task_info):
    """
    Verify that the repository content was exported to the local filesystem.
    
    Criteria:
    1. Export directory exists (/home/ga/repo_export).
    2. Directory was created/modified AFTER task start (anti-gaming).
    3. Contains the expected artifact (commons-lang3-3.14.0.jar).
    4. Total export size is reasonable (>500KB).
    5. Metadata is present (indicating "Include Metadata" was checked).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load task metadata for expected values
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_export_size_bytes', 500000)
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Extract results
    dir_exists = result.get('export_dir_exists', False)
    fresh_creation = result.get('dir_created_during_task', False)
    artifact_found = result.get('artifact_found', False)
    metadata_found = result.get('metadata_found', False)
    total_size = result.get('total_size_bytes', 0)
    
    score = 0
    feedback_parts = []
    
    # Check 1: Directory Exists (15 pts)
    if dir_exists:
        score += 15
        feedback_parts.append("Export directory found")
    else:
        feedback_parts.append("Export directory /home/ga/repo_export NOT found")
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback_parts)}
        
    # Check 2: Fresh Creation (15 pts)
    if fresh_creation:
        score += 15
        feedback_parts.append("Export timestamp valid")
    else:
        feedback_parts.append("Export directory timestamp is stale (pre-dates task)")
        
    # Check 3: Artifact Content (25 pts)
    if artifact_found:
        score += 25
        feedback_parts.append("Expected artifact found in export")
    else:
        feedback_parts.append("Expected artifact (commons-lang3) missing from export")
        
    # Check 4: Metadata (15 pts)
    if metadata_found:
        score += 15
        feedback_parts.append("Metadata files found")
    else:
        feedback_parts.append("Metadata missing (did you check 'Include Metadata'?)")
        
    # Check 5: Size Validation (30 pts)
    if total_size >= min_size:
        score += 30
        feedback_parts.append(f"Export size valid ({total_size} bytes)")
    else:
        feedback_parts.append(f"Export size too small ({total_size} < {min_size})")
        
    passed = score >= 60 and dir_exists and artifact_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }