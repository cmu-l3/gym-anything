#!/usr/bin/env python3
"""
Verifier for Compare Implementation Approaches task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_comparison_task(traj, env_info, task_info):
    """
    Verify that implementation comparison task was completed correctly.

    Checks:
    1. DECISION.md exists with sufficient content (>50 chars)
    2. Exactly one implementation has .archived extension
    3. One implementation remains active (no extension)
    4. Decision mentions the chosen implementation
    5. Decision includes justification keywords
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    workspace_path = "/home/ga/workspace/data_pipeline"
    temp_dir = tempfile.mkdtemp(prefix='compare_verify_')

    try:
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []

        # Criterion 1: Check DECISION.md exists with content
        decision_file = os.path.join(temp_dir, "DECISION.md")
        try:
            copy_from_env(f"{workspace_path}/DECISION.md", decision_file)
            
            if not os.path.exists(decision_file) or os.path.getsize(decision_file) == 0:
                feedback_parts.append("❌ DECISION.md not found or empty")
            else:
                content = read_file_content(decision_file)
                if len(content.strip()) < 50:
                    feedback_parts.append(f"❌ DECISION.md too short ({len(content)} chars, need 50+)")
                else:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ DECISION.md exists with sufficient content ({len(content)} chars)")
        except Exception as e:
            feedback_parts.append(f"❌ Could not read DECISION.md: {str(e)}")
            content = ""

        # Check which files exist
        iter_active = False
        func_active = False
        iter_archived = False
        func_archived = False

        # Try to copy each possible file
        iter_active_path = os.path.join(temp_dir, "data_processor_iterative.py")
        func_active_path = os.path.join(temp_dir, "data_processor_functional.py")
        iter_archived_path = os.path.join(temp_dir, "data_processor_iterative.py.archived")
        func_archived_path = os.path.join(temp_dir, "data_processor_functional.py.archived")

        try:
            copy_from_env(f"{workspace_path}/data_processor_iterative.py", iter_active_path)
            if os.path.exists(iter_active_path) and os.path.getsize(iter_active_path) > 0:
                iter_active = True
        except:
            pass

        try:
            copy_from_env(f"{workspace_path}/data_processor_functional.py", func_active_path)
            if os.path.exists(func_active_path) and os.path.getsize(func_active_path) > 0:
                func_active = True
        except:
            pass

        try:
            copy_from_env(f"{workspace_path}/data_processor_iterative.py.archived", iter_archived_path)
            if os.path.exists(iter_archived_path) and os.path.getsize(iter_archived_path) > 0:
                iter_archived = True
        except:
            pass

        try:
            copy_from_env(f"{workspace_path}/data_processor_functional.py.archived", func_archived_path)
            if os.path.exists(func_archived_path) and os.path.getsize(func_archived_path) > 0:
                func_archived = True
        except:
            pass

        # Criterion 2: Exactly one implementation archived
        archived_count = sum([iter_archived, func_archived])
        if archived_count == 1:
            criteria_passed += 1
            archived_name = "iterative" if iter_archived else "functional"
            feedback_parts.append(f"✅ Exactly one implementation archived ({archived_name})")
        elif archived_count == 0:
            feedback_parts.append("❌ No implementation archived (need to add .archived extension)")
        else:
            feedback_parts.append(f"❌ {archived_count} implementations archived (should be exactly 1)")

        # Criterion 3: Exactly one active implementation remains
        active_count = sum([iter_active, func_active])
        if active_count == 1:
            criteria_passed += 1
            active_name = "iterative" if iter_active else "functional"
            feedback_parts.append(f"✅ One implementation remains active ({active_name})")
        elif active_count == 0:
            feedback_parts.append("❌ No active implementation found (both archived or deleted?)")
        elif active_count == 2:
            feedback_parts.append("❌ Both implementations still active (need to archive one)")

        # Determine chosen implementation
        chosen = None
        if iter_active and not func_active:
            chosen = 'iterative'
        elif func_active and not iter_active:
            chosen = 'functional'

        # Criterion 4: Consistency between decision and archival
        if chosen and content:
            content_lower = content.lower()
            if chosen in content_lower:
                criteria_passed += 1
                feedback_parts.append(f"✅ Decision mentions chosen implementation ({chosen})")
            else:
                feedback_parts.append(f"❌ Decision doesn't mention '{chosen}' (the active implementation)")
        elif not chosen:
            feedback_parts.append("❌ Cannot determine chosen implementation from file state")
        
        # Criterion 5: Justification keywords present
        if content:
            content_lower = content.lower()
            justification_keywords = [
                'performance', 'faster', 'slower', 'speed',
                'readable', 'readability', 'clear', 'simple', 'complex',
                'maintain', 'maintainability', 'maintainable',
                'because', 'reason', 'trade-off', 'tradeoff',
                'pythonic', 'idiomatic', 'elegant'
            ]
            found_keywords = [kw for kw in justification_keywords if kw in content_lower]
            
            if found_keywords:
                criteria_passed += 1
                feedback_parts.append(f"✅ Decision includes justification (keywords: {', '.join(found_keywords[:3])})")
            else:
                feedback_parts.append("❌ Decision lacks clear justification (no reasoning keywords found)")
        else:
            feedback_parts.append("❌ Cannot check justification (no decision content)")

        # Calculate score and result
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80

        feedback_parts.append(f"\nCriteria passed: {criteria_passed}/{total_criteria}")
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
