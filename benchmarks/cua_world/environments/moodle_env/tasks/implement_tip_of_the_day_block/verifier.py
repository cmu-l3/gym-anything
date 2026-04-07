#!/usr/bin/env python3
"""Verifier for Implement Tip of the Day Block task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_implement_tip_of_the_day_block(traj, env_info, task_info):
    """
    Verify that the Glossary and Random Entry Block were created and configured correctly.
    
    Scoring (100 points):
    - Glossary Created (25 pts): Glossary exists in BIO101 with correct name.
    - Entries Populated (25 pts): Both specific entries exist.
    - Block Added (25 pts): Random glossary block exists in course context.
    - Block Configured (25 pts): Block has correct title and is linked to the glossary.
    
    Pass Threshold: 75 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/implement_tip_of_the_day_block_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Glossary Created (25 pts)
        glossary_found = result.get('glossary_found', False)
        glossary_name = result.get('glossary_name', '')
        
        if glossary_found:
            # Check name match (flexible matching already done in export, but strict check here)
            if "student study strategies" in glossary_name.lower():
                score += 25
                subscores['glossary_created'] = True
                feedback_parts.append("Glossary 'Student Study Strategies' created")
            else:
                score += 10 # Partial for creating *a* glossary
                subscores['glossary_created'] = False
                feedback_parts.append(f"Glossary created but name mismatch: '{glossary_name}'")
        else:
            subscores['glossary_created'] = False
            feedback_parts.append("Glossary NOT found")
            
        # Criterion 2: Entries Populated (25 pts)
        has_spaced = result.get('has_spaced_repetition', False)
        has_recall = result.get('has_active_recall', False)
        
        if has_spaced and has_recall:
            score += 25
            subscores['entries_correct'] = True
            feedback_parts.append("Both glossary entries found")
        elif has_spaced or has_recall:
            score += 12
            subscores['entries_correct'] = False
            feedback_parts.append("One glossary entry found, one missing")
        else:
            subscores['entries_correct'] = False
            if glossary_found:
                feedback_parts.append("Glossary entries missing")
                
        # Criterion 3: Block Added (25 pts)
        block_found = result.get('block_found', False)
        initial_block_count = int(result.get('initial_block_count', 0))
        current_block_count = int(result.get('current_block_count', 0))
        newly_added = current_count = current_block_count > initial_block_count
        
        if block_found and newly_added:
            score += 25
            subscores['block_added'] = True
            feedback_parts.append("Random Glossary Entry block added")
        elif block_found:
            # Maybe pre-existing, but found valid config
            score += 15
            subscores['block_added'] = True
            feedback_parts.append("Block found (pre-existing or count issue)")
        else:
            subscores['block_added'] = False
            feedback_parts.append("Block NOT found in course sidebar")
            
        # Criterion 4: Block Configured (25 pts)
        title_match = result.get('block_title_match', False)
        link_match = result.get('block_linked_glossary_match', False)
        
        if title_match and link_match:
            score += 25
            subscores['block_configured'] = True
            feedback_parts.append("Block title and linkage correct")
        elif title_match:
            score += 10
            subscores['block_configured'] = False
            feedback_parts.append("Block title correct, but not linked to glossary")
        elif link_match:
            score += 10
            subscores['block_configured'] = False
            feedback_parts.append("Block linked to glossary, but title mismatch")
        else:
            subscores['block_configured'] = False
            if block_found:
                feedback_parts.append("Block configuration incorrect")

        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}