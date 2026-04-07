#!/usr/bin/env python3
"""
Verifier for manage_versioned_publications@1

Criteria:
1. Public Proxy exists in 'Customer Portal'.
2. Internal Proxy exists in 'Engineering Internal'.
3. Internal Proxy version > Public Proxy version.
4. Internal Proxy content digest != Public Proxy content digest.
5. Source document content digest == Internal Proxy content digest (Source was updated).

This confirms the split-horizon publication pattern.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_versioned_publications(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    source = result.get('source', {})
    public = result.get('public_proxy', {})
    internal = result.get('internal_proxy', {})

    # 1. Check Public Proxy (20 pts)
    if public.get('exists'):
        score += 20
        feedback_parts.append("Public proxy published.")
    else:
        feedback_parts.append("Public proxy missing.")

    # 2. Check Internal Proxy (20 pts)
    if internal.get('exists'):
        score += 20
        feedback_parts.append("Internal proxy published.")
    else:
        feedback_parts.append("Internal proxy missing.")

    # Stop here if basic publishing failed
    if not public.get('exists') or not internal.get('exists'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "FAILED: Missing required publications. " + " ".join(feedback_parts)
        }

    # 3. Version Divergence (30 pts)
    # Parse version labels (e.g. "0.1", "1.0", "2.1+")
    def parse_version(v_str):
        try:
            return float(v_str.replace('+', ''))
        except:
            return 0.0

    pub_ver = parse_version(public.get('versionLabel', '0.0'))
    int_ver = parse_version(internal.get('versionLabel', '0.0'))

    if int_ver > pub_ver:
        score += 30
        feedback_parts.append(f"Versions diverge correctly (Public: {pub_ver}, Internal: {int_ver}).")
    else:
        feedback_parts.append(f"Versions did not diverge (Public: {pub_ver}, Internal: {int_ver}). Did you create a new version?")

    # 4. Content Divergence (20 pts)
    pub_digest = public.get('digest')
    int_digest = internal.get('digest')

    if pub_digest and int_digest and pub_digest != int_digest:
        score += 20
        feedback_parts.append("Content differs between public and internal.")
    else:
        feedback_parts.append("Content is identical in both sections. Source file likely not updated.")

    # 5. Source Update Check (10 pts)
    src_digest = source.get('digest')
    if src_digest == int_digest and src_digest != pub_digest:
        score += 10
        feedback_parts.append("Source document matches internal draft.")
    
    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }