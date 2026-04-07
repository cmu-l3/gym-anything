#!/usr/bin/env python3
"""Verifier for Create Competency Framework task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_competency_framework(traj, env_info, task_info):
    """
    Verify creation of competency framework, competencies, and course links.
    
    Scoring Criteria:
    1. Framework exists with correct ID 'DLF001' (15 pts)
    2. Framework name contains 'Digital Literacy' (10 pts)
    3. Competencies Created: 10 pts each for DL-IL, DL-DC, DL-DA (Max 30 pts)
    4. Competencies Linked to Course: 10 pts each (Max 30 pts)
    5. Scale Configuration: Valid scale ID assigned (15 pts)
    
    Pass threshold: 55 points (Framework + ~2 competencies created)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Load result JSON
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_competency_framework_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        subscores = {}
        
        # 1. Framework Existence (15 pts)
        fw_found = result.get('framework_found', False)
        created_during = result.get('created_during_task', False)
        
        if fw_found:
            if created_during:
                score += 15
                subscores['framework_exists'] = True
                feedback_parts.append("Framework 'DLF001' created")
            else:
                # Penalize pre-existing (or barely modified) framework
                score += 5 
                subscores['framework_exists'] = True
                feedback_parts.append("Framework exists but was NOT created during task")
        else:
            subscores['framework_exists'] = False
            feedback_parts.append("Framework 'DLF001' not found")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Framework not created. Stopping verification.",
                "subscores": subscores
            }

        # 2. Framework Name (10 pts)
        name = result.get('framework_name', '')
        if 'Digital Literacy' in name:
            score += 10
            feedback_parts.append("Framework name correct")
        else:
            feedback_parts.append(f"Framework name mismatch ('{name}')")
            
        # 3. Competencies Created (30 pts - 10 each)
        comp_count = result.get('competencies_found_count', 0)
        # Use boolean flags for detailed feedback
        il = result.get('competency_il_found', False)
        dc = result.get('competency_dc_found', False)
        da = result.get('competency_da_found', False)
        
        comp_score = 0
        if il: comp_score += 10
        if dc: comp_score += 10
        if da: comp_score += 10
        
        score += comp_score
        feedback_parts.append(f"Competencies created: {comp_count}/3")
        
        # 4. Competencies Linked to Course (30 pts - 10 each)
        # Note: export script counts total valid links for our framework
        link_count = result.get('links_to_course_count', 0)
        # Cap at 3 for scoring purposes
        link_score = min(link_count, 3) * 10
        score += link_score
        feedback_parts.append(f"Competencies linked to CS101: {link_count}/3")
        
        # 5. Scale Configuration (15 pts)
        scale_id = int(result.get('framework_scale_id', 0))
        if scale_id > 0:
            score += 15
            feedback_parts.append("Scale assigned")
        else:
            feedback_parts.append("No scale assigned to framework")

        # Final check
        passed = score >= 55
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}