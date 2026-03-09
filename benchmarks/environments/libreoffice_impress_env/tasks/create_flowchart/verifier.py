#!/usr/bin/env python3
"""
Verifier for Create Flowchart task
"""

import sys
import os
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from impress_verification_utils import (
    copy_and_parse_presentation,
    get_slide_shapes,
    count_shapes_on_slide,
    cleanup_verification_environment,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_flowchart_created(traj, env_info, task_info):
    """
    Verify flowchart creation.
    
    Checks:
    1. Multiple shapes present (at least 4)
    2. Connectors present (at least 2)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_path = "/home/ga/Documents/Presentations/flowchart_test.odp"
    success, presentation, error, temp_dir = copy_and_parse_presentation(
        container_path,
        copy_from_env,
        file_format='odp'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": error}

    try:
        criteria_passed = 0
        total_criteria = 2
        feedback_parts = []
        
        # Get shapes from first slide
        shapes = get_slide_shapes(presentation, 0)
        shape_count = len(shapes)
        
        # Count connectors
        connector_count = sum(1 for s in shapes if 'connector' in str(s.get('type', '')).lower())
        
        # Criterion 1: Multiple shapes (at least 4)
        if shape_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Multiple shapes present: {shape_count}")
        else:
            feedback_parts.append(f"❌ Insufficient shapes: {shape_count} (need at least 4)")
        
        # Criterion 2: Connectors present
        if connector_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Connectors present: {connector_count}")
        else:
            feedback_parts.append(f"❌ Insufficient connectors: {connector_count} (need at least 2)")
        
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_environment(temp_dir)
