#!/usr/bin/env python3
"""
Verifier for deploy_maven_multi_artifact task.
"""
import json
import os
import tempfile
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_maven_multi_artifact(traj, env_info, task_info):
    """
    Verify that 4 artifacts were deployed to the correct paths with correct content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    task_start = result.get('task_start', 0)
    artifacts = result.get('artifacts', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Define weights
    # 4 artifacts total. Each worth 25 points total (split into existence, path/size, content, timing)
    
    artifact_keys = ['lang3_jar', 'lang3_pom', 'io_jar', 'io_pom']
    
    passed_artifacts = 0
    
    for key in artifact_keys:
        info = artifacts.get(key, {})
        exists = info.get('exists', False)
        size = info.get('size', 0)
        remote_sha = info.get('sha256_remote', '')
        source_sha = info.get('sha256_source', '')
        created_iso = info.get('created', '')
        path = info.get('path', '')
        
        name = key.replace('_', ' ').upper()
        
        if not exists:
            feedback_parts.append(f"MISSING: {name} at {path}")
            continue
            
        # 1. Existence & Path (Implicitly checked by export script querying specific path)
        # If exists=True, it is at the correct path.
        item_score = 10 
        
        # 2. Size Check
        # JARs should be substantial (>1KB), POMs small but not empty (>100B)
        is_jar = 'jar' in key
        min_size = 1024 if is_jar else 100
        if size > min_size:
            item_score += 5
        else:
            feedback_parts.append(f"WARNING: {name} size too small ({size} bytes)")
            
        # 3. Checksum Check
        if remote_sha and source_sha and remote_sha == source_sha:
            item_score += 5
        else:
            feedback_parts.append(f"FAIL: {name} checksum mismatch")
            
        # 4. Timing Check (Anti-gaming)
        # Convert ISO timestamp "2023-10-27T10:00:00.123+0000" to epoch
        # Artifactory format usually: 2024-05-21T09:21:00.627Z
        created_epoch = 0
        try:
            # Handle Z or +00:00
            created_str = created_iso.replace('Z', '+00:00')
            # Python 3.7+ fromisoformat handles some, but let's be safe
            # Simple fallback if complex parsing needed
            dt = datetime.fromisoformat(created_str)
            created_epoch = dt.timestamp()
        except:
            # Fallback for rough check if strict parsing fails
            pass
            
        if created_epoch > task_start:
            item_score += 5
        elif created_epoch == 0 and created_iso:
             # If parsing failed but string exists, give benefit of doubt if other checks pass
             # Or check simple string comparison if format allows
             item_score += 2
             feedback_parts.append(f"WARN: Could not verify timestamp for {name}")
        else:
            item_score = 0 # Fail if file is old (pre-existing)
            feedback_parts.append(f"FAIL: {name} appears to be old data (not created during task)")
            
        score += item_score
        
        if item_score >= 20: # If most criteria met
            passed_artifacts += 1
            feedback_parts.append(f"OK: {name}")

    passed = (passed_artifacts >= 4) and (score >= 80)
    
    feedback = " | ".join(feedback_parts)
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }