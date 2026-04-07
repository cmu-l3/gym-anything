#!/usr/bin/env python3
"""Verifier for Reorganize Course Catalog task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reorganize_course_catalog(traj, env_info, task_info):
    """
    Verify the Moodle course catalog restructuring.

    Scoring (100 points):
    1. Category 'Life Sciences' created (20 pts)
    2. 'Life Sciences' metadata correct: ID=LIFESCI, Desc, Parent=0 (15 pts)
    3. BIO101 moved to 'Life Sciences' (30 pts)
    4. Sub-category 'Archived Life Sciences' created (15 pts)
    5. Sub-category is hidden (Visible=0) and parent is 'Life Sciences' (20 pts)

    Pass threshold: 65 points (Must include creation + move)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/reorganize_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Life Sciences Category Existence (20 pts)
        lifesci = result.get('lifesci', {})
        lifesci_found = result.get('lifesci_found', False)
        
        if lifesci_found:
            score += 20
            feedback_parts.append("'Life Sciences' category found")
        else:
            feedback_parts.append("'Life Sciences' category NOT found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }

        # 2. Life Sciences Metadata (15 pts)
        # Check ID Number, Description, Parent
        ls_idnum = lifesci.get('idnumber', '')
        ls_desc = lifesci.get('description', '')
        ls_parent = int(lifesci.get('parent', -1))
        
        meta_ok = True
        if ls_idnum != 'LIFESCI':
            meta_ok = False
            feedback_parts.append(f"Wrong ID Number: {ls_idnum}")
        if 'living organisms' not in ls_desc.lower():
            meta_ok = False
            feedback_parts.append("Description missing keywords")
        if ls_parent != 0:
            meta_ok = False
            feedback_parts.append("Not a top-level category")
            
        if meta_ok:
            score += 15
            feedback_parts.append("Category metadata correct")
        else:
            # Partial credit for being Top Level at least
            if ls_parent == 0:
                score += 5

        # 3. BIO101 Course Move (30 pts)
        bio101_cat = str(result.get('bio101_category_id', '0'))
        lifesci_id = str(lifesci.get('id', '1'))
        
        if bio101_cat == lifesci_id:
            score += 30
            subscores["course_moved"] = True
            feedback_parts.append("BIO101 moved successfully")
        else:
            subscores["course_moved"] = False
            feedback_parts.append(f"BIO101 not in new category (CatID: {bio101_cat})")

        # 4. Archived Sub-category Existence (15 pts)
        archive = result.get('archive', {})
        archive_found = result.get('archive_found', False)
        
        if archive_found:
            score += 15
            feedback_parts.append("'Archived' sub-category found")
        else:
            feedback_parts.append("'Archived' sub-category NOT found")

        # 5. Archived Configuration (20 pts)
        # Must be child of Life Sciences AND Hidden
        arch_parent = str(archive.get('parent', '0'))
        arch_visible = int(archive.get('visible', 1))
        
        config_score = 0
        if arch_parent == lifesci_id:
            config_score += 10
            feedback_parts.append("Parent correct")
        else:
            feedback_parts.append("Wrong parent category")
            
        if arch_visible == 0:
            config_score += 10
            feedback_parts.append("Category hidden")
        else:
            feedback_parts.append("Category still visible")
            
        score += config_score

        # Final check
        # Threshold 65: Needs (20+15) or (20+30+15) etc.
        # Ideally: Created(20) + Moved(30) + Archive(15) = 65
        passed = score >= 65 and subscores.get("course_moved", False)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}