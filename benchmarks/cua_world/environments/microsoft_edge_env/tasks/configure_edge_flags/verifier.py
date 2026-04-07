#!/usr/bin/env python3
"""
Verifier for configure_edge_flags task.

Scoring (100 points total):
- 15 points per correctly configured flag (5 flags = 75 points)
  - smooth-scrolling@2 (Disabled)
  - enable-parallel-downloading@1 (Enabled)
  - enable-force-dark@1 (Enabled)
  - enable-quic@1 (Enabled)
  - tab-hover-card-images@2 (Disabled)
- 25 points for configuration document
  - 10 points: Exists and created during task
  - 15 points: Content mentions keywords for flags

Pass Threshold: 65 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_edge_flags(traj, env_info, task_info):
    """
    Verify that Edge flags were configured correctly and documented.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_flags_map = metadata.get('required_flags', {
        "smooth-scrolling": "2",
        "enable-parallel-downloading": "1",
        "enable-force-dark": "1",
        "enable-quic": "1",
        "tab-hover-card-images": "2"
    })

    # Retrieve result file
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

    score = 0
    feedback_parts = []
    
    # 1. Verify Flags (75 points max)
    # Flags in Local State are stored as strings like "flag-name@choice"
    # choice 1 usually Enabled, 2 usually Disabled (for simple boolean flags)
    
    current_flags = result.get('flags', [])
    current_flags_dict = {}
    
    # Parse current flags into a dict {name: choice}
    for flag_str in current_flags:
        if '@' in flag_str:
            name, choice = flag_str.split('@', 1)
            current_flags_dict[name] = choice
    
    correct_flags_count = 0
    
    for flag_name, required_choice in required_flags_map.items():
        actual_choice = current_flags_dict.get(flag_name)
        
        state_label = "Enabled" if required_choice == "1" else "Disabled"
        
        if actual_choice == required_choice:
            score += 15
            correct_flags_count += 1
            feedback_parts.append(f"✓ {flag_name} set to {state_label}")
        else:
            feedback_parts.append(f"✗ {flag_name} incorrect (found: {actual_choice or 'Default'}, expected: {state_label})")

    # 2. Verify Documentation (25 points max)
    config_file_info = result.get('config_file', {})
    
    if config_file_info.get('exists') and config_file_info.get('created_during_task'):
        score += 10
        feedback_parts.append("✓ Configuration document created")
        
        # Check content quality
        content = config_file_info.get('content', '').lower()
        keywords = ["scrolling", "parallel", "dark", "quic", "hover"]
        found_keywords = sum(1 for k in keywords if k in content)
        
        if found_keywords >= 3:
            score += 15
            feedback_parts.append(f"✓ Document mentions {found_keywords}/5 flag keywords")
        elif found_keywords > 0:
            score += 5
            feedback_parts.append(f"⚠ Document incomplete ({found_keywords}/5 flag keywords)")
        else:
            feedback_parts.append("✗ Document content missing relevant keywords")
            
    elif config_file_info.get('exists'):
        # Exists but pre-dated task (shouldn't happen due to setup script)
        feedback_parts.append("✗ Configuration document stale (not created during task)")
    else:
        feedback_parts.append("✗ Configuration document missing")

    # Final result
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }