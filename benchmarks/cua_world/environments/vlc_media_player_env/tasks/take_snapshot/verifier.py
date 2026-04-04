#!/usr/bin/env python3
"""
Verifier for Take Snapshot task
"""

import sys
import os
import logging
import tempfile

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from vlc_verification_utils import (
    verify_snapshot_exists,
    verify_image_quality,
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_take_snapshot(traj, env_info, task_info):
    """
    Verify take snapshot task completion.
    
    Checks:
    1. Snapshot file exists
    2. Snapshot has reasonable quality
    3. Completion marker exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    criteria_met = 0
    total_criteria = 3
    feedback_parts = []
    
    # Criterion 1 & 2: Verify snapshot exists and has quality
    success, file_info, error = setup_verification_environment(
        copy_from_env,
        "/tmp/vlc_take_snapshot.png",
        file_type='image'
    )
    
    if success:
        image_data = file_info.get('data', {})
        
        criteria_met += 1
        feedback_parts.append("✅ Snapshot captured")
        
        # Check image properties
        if image_data.get('size_kb', 0) > 10:  # Lowered from 50 KB
            criteria_met += 1
            feedback_parts.append(f"✅ Snapshot quality OK ({image_data.get('size_kb', 0):.1f} KB)")
        else:
            feedback_parts.append("⚠️ Snapshot may be low quality")
        
        cleanup_verification_environment(file_info.get('temp_dir'))
    else:
        feedback_parts.append(f"❌ Snapshot not found: {error}")
    
    # Criterion 3: Completion marker
    temp_marker = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/vlc_take_snapshot_completed.txt", temp_marker.name)
        criteria_met += 1
        feedback_parts.append("✅ Task completed")
        os.unlink(temp_marker.name)
    except Exception:
        feedback_parts.append("⚠️ Completion marker not found")
    
    # Calculate score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 65
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
