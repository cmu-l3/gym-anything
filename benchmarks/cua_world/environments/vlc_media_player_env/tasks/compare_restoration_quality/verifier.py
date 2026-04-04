#!/usr/bin/env python3
"""
Verifier for Compare Restoration Quality task
"""

import sys
import os
import logging
import tempfile
import json
from pathlib import Path

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_image_quality,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compare_restoration_quality(traj, env_info, task_info):
    """
    Verify compare restoration quality task completion.
    
    Checks:
    1. Original video snapshot exists with proper naming
    2. Restored video snapshot exists with proper naming
    3. Both snapshots are valid images with reasonable quality
    4. Snapshots were captured in temporal proximity (same session)
    5. Evidence of multi-window workflow (multiple VLC instances)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 5
    feedback_parts = []
    
    # Read metadata JSON
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vlc_comparison_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            metadata = json.load(f)
        os.unlink(temp_meta.name)
    except Exception as e:
        logger.warning(f"Could not read metadata: {e}")
        metadata = {}
    
    # Criterion 1: Check for original snapshot
    original_snapshot = None
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_comparison_original.png",
        file_type='image'
    )
    
    if success:
        original_data = file_info.get('data', {})
        original_size = original_data.get('size_kb', 0)
        original_path = file_info.get('filepath', '')
        
        if original_size > 20:
            criteria_met += 1
            feedback_parts.append(f"✅ Original snapshot found ({original_size:.1f} KB)")
            original_snapshot = {
                'path': original_path,
                'size': original_size,
                'mtime': Path(original_path).stat().st_mtime if Path(original_path).exists() else 0
            }
        else:
            feedback_parts.append(f"⚠️ Original snapshot too small ({original_size:.1f} KB)")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
    else:
        feedback_parts.append(f"❌ Original snapshot not found")
    
    # Criterion 2: Check for restored snapshot
    restored_snapshot = None
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_comparison_restored.png",
        file_type='image'
    )
    
    if success:
        restored_data = file_info.get('data', {})
        restored_size = restored_data.get('size_kb', 0)
        restored_path = file_info.get('filepath', '')
        
        if restored_size > 20:
            criteria_met += 1
            feedback_parts.append(f"✅ Restored snapshot found ({restored_size:.1f} KB)")
            restored_snapshot = {
                'path': restored_path,
                'size': restored_size,
                'mtime': Path(restored_path).stat().st_mtime if Path(restored_path).exists() else 0
            }
        else:
            feedback_parts.append(f"⚠️ Restored snapshot too small ({restored_size:.1f} KB)")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
    else:
        feedback_parts.append(f"❌ Restored snapshot not found")
    
    # Criterion 3: Both snapshots valid (already checked via size, award if both exist)
    if original_snapshot and restored_snapshot:
        criteria_met += 1
        feedback_parts.append("✅ Both snapshots are valid images")
    else:
        feedback_parts.append("❌ Missing one or both snapshots")
    
    # Criterion 4: Check temporal proximity (captured in same session)
    if original_snapshot and restored_snapshot:
        time_diff = abs(original_snapshot['mtime'] - restored_snapshot['mtime'])
        
        if time_diff < 60:  # Within 60 seconds
            criteria_met += 1
            feedback_parts.append(f"✅ Snapshots captured within {time_diff:.0f}s (same session)")
        elif time_diff < 300:  # Within 5 minutes
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Snapshots captured {time_diff:.0f}s apart (acceptable)")
        else:
            feedback_parts.append(f"⚠️ Snapshots captured {time_diff:.0f}s apart (may not be from same session)")
    else:
        feedback_parts.append("❌ Cannot verify temporal proximity (missing snapshots)")
    
    # Criterion 5: Check for evidence of multi-window workflow
    vlc_instances = metadata.get('vlc_instances', 0)
    
    if vlc_instances >= 2:
        criteria_met += 1
        feedback_parts.append(f"✅ Multiple VLC instances detected ({vlc_instances})")
    elif vlc_instances == 1:
        # Give partial credit - user might have used single instance creatively
        criteria_met += 0.5
        feedback_parts.append("⚠️ Single VLC instance (may have used playlist/sequential approach)")
    else:
        feedback_parts.append("⚠️ Could not detect VLC instance count")
    
    # Check completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_compare_completed.txt", temp_marker.name)
        with open(temp_marker.name, 'r') as f:
            content = f.read()
        if "completed" in content.lower():
            feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        pass
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    feedback = " | ".join(feedback_parts)
    
    # Add helpful summary
    if passed:
        summary = "Task completed successfully - synchronized comparison workflow demonstrated"
    elif score >= 40:
        summary = "Partial completion - some comparison elements present but workflow incomplete"
    else:
        summary = "Task not completed - insufficient evidence of comparison workflow"
    
    final_feedback = f"{summary} | {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }