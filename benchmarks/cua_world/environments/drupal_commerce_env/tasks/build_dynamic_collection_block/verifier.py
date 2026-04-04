#!/usr/bin/env python3
"""
Verifier for build_dynamic_collection_block task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_build_dynamic_collection_block(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        # 1. Vocabulary (10 pts)
        if int(result.get('vocab_exists', 0)) > 0:
            score += 10
            feedback_parts.append("Vocabulary 'Collections' created")
        else:
            feedback_parts.append("Vocabulary missing")
            
        # 2. Term (10 pts)
        if result.get('term_exists') and result.get('term_vid') == 'collections':
            score += 10
            feedback_parts.append("Term 'Summer Collection' created in correct vocab")
        elif result.get('term_exists'):
            score += 5
            feedback_parts.append("Term created but in wrong vocab")
        else:
            feedback_parts.append("Term missing")
            
        # 3. Field (20 pts)
        if int(result.get('field_storage_exists', 0)) > 0 and int(result.get('field_instance_exists', 0)) > 0:
            score += 20
            feedback_parts.append("Field 'field_collection' created correctly")
        elif int(result.get('field_storage_exists', 0)) > 0:
            score += 10
            feedback_parts.append("Field storage created, but instance missing")
        else:
            feedback_parts.append("Field missing")
            
        # 4. Products Tagged (20 pts)
        tagged_score = 0
        if result.get('sony_tagged'): tagged_score += 10
        if result.get('logi_tagged'): tagged_score += 10
        score += tagged_score
        if tagged_score == 20:
            feedback_parts.append("Both products tagged")
        elif tagged_score > 0:
            feedback_parts.append("Some products tagged")
        else:
            feedback_parts.append("No products tagged")
            
        # 5. View Exists (20 pts)
        if int(result.get('view_exists', 0)) > 0:
            score += 20
            feedback_parts.append("View 'summer_collection' created")
        else:
            feedback_parts.append("View missing")
            
        # 6. Block Placed / Frontend (20 pts)
        # We verify this either by config existence OR frontend visibility (robustness)
        if int(result.get('block_placed', 0)) > 0:
            score += 10
            feedback_parts.append("Block config placed")
        
        if result.get('visible_on_homepage'):
            score += 10
            feedback_parts.append("Block visible on homepage with products")
        elif result.get('block_title_visible'):
            score += 5
            feedback_parts.append("Block title visible, but products missing")
        else:
            feedback_parts.append("Block not visible on homepage")
            
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}