#!/usr/bin/env python3
"""
Verifier for Trace Error Source task
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_trace_error(traj, env_info, task_info):
    """
    Verify that error tracing and fixing was completed correctly.
    
    Checks:
    1. investigation_notes.md exists with substantial content
    2. Notes mention line 67
    3. Notes discuss None/NoneType issue
    4. data_processor.py has explanatory comments
    5. Defensive None check implemented
    6. Fix is in correct location (near line 67)
    7. Investigation proposes a solution
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='trace_error_verify_')
    
    try:
        workspace_path = "/home/ga/workspace/user_service"
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Criterion 1: investigation_notes.md exists with content
        notes_path = f"{workspace_path}/investigation_notes.md"
        notes_temp = os.path.join(temp_dir, "investigation_notes.md")
        notes_exists = False
        notes_content = ""
        
        try:
            copy_from_env(notes_path, notes_temp)
            if os.path.exists(notes_temp) and os.path.getsize(notes_temp) > 0:
                notes_content = read_file_content(notes_temp)
                if len(notes_content.strip()) >= 100:
                    criteria_passed += 1
                    notes_exists = True
                    feedback_parts.append(f"✅ investigation_notes.md exists with content ({len(notes_content)} chars)")
                else:
                    feedback_parts.append(f"❌ investigation_notes.md too short ({len(notes_content)} chars, need >100)")
            else:
                feedback_parts.append("❌ investigation_notes.md is empty")
        except Exception as e:
            feedback_parts.append(f"❌ investigation_notes.md not found: {str(e)[:50]}")
        
        # Criterion 2: Notes mention line 67
        if notes_exists:
            if '67' in notes_content:
                criteria_passed += 1
                feedback_parts.append("✅ Investigation mentions line 67")
            else:
                feedback_parts.append("❌ Investigation should mention line 67 where error occurred")
        else:
            feedback_parts.append("❌ Cannot check line number (notes not found)")
        
        # Criterion 3: Notes discuss root cause (None/NoneType)
        if notes_exists:
            root_cause_patterns = ['none', 'nonetype', 'null', 'extract_address_info', 'address_info']
            has_root_cause = any(pattern in notes_content.lower() for pattern in root_cause_patterns)
            if has_root_cause:
                criteria_passed += 1
                feedback_parts.append("✅ Root cause analysis present (mentions None/address_info)")
            else:
                feedback_parts.append("❌ Root cause not clearly explained (should mention None from extract_address_info)")
        else:
            feedback_parts.append("❌ Cannot check root cause (notes not found)")
        
        # Check data_processor.py modifications
        processor_path = f"{workspace_path}/data_processor.py"
        processor_temp = os.path.join(temp_dir, "data_processor.py")
        processor_exists = False
        processor_content = ""
        
        try:
            copy_from_env(processor_path, processor_temp)
            if os.path.exists(processor_temp) and os.path.getsize(processor_temp) > 0:
                processor_content = read_file_content(processor_temp)
                processor_exists = True
            else:
                feedback_parts.append("❌ data_processor.py is empty")
        except Exception as e:
            feedback_parts.append(f"❌ data_processor.py not found: {str(e)[:50]}")
        
        # Criterion 4: Explanatory comments added
        if processor_exists:
            comment_patterns = [
                r'#.*[Bb]ug',
                r'#.*[Ee]rror',
                r'#.*[Nn]one',
                r'#.*[Ff]ix',
                r'#.*[Cc]heck',
                r'#.*[Vv]alidat',
                r'#.*[Rr]eturn',
                r'#.*[Cc]an.*[Rr]eturn',
                r'#.*address_info'
            ]
            has_comment = any(re.search(pattern, processor_content) for pattern in comment_patterns)
            
            if has_comment:
                criteria_passed += 1
                feedback_parts.append("✅ Explanatory comments added to code")
            else:
                feedback_parts.append("❌ No explanatory comments found (should explain the bug)")
        else:
            feedback_parts.append("❌ Cannot check comments (file not found)")
        
        # Criterion 5: Defensive None check implemented
        if processor_exists:
            defensive_patterns = [
                r'if\s+address_info\s+is\s+not\s+None',
                r'if\s+address_info\s*:',
                r'if\s+not\s+address_info\s*:',
                r'address_info\s+or\s+\{',
                r'if\s+address_info\s+is\s+None',
                r'address_info\s+if\s+address_info\s+else',
                r'address_info\s*\)\s+else',
            ]
            has_defensive = any(re.search(pattern, processor_content) for pattern in defensive_patterns)
            
            if has_defensive:
                criteria_passed += 1
                feedback_parts.append("✅ Defensive None check added")
            else:
                feedback_parts.append("❌ No defensive None check found (should check before calling .get())")
        else:
            feedback_parts.append("❌ Cannot check defensive code (file not found)")
        
        # Criterion 6: Fix is in correct location (near line 67)
        if processor_exists:
            lines = processor_content.split('\n')
            if len(lines) >= 67:
                # Check lines 60-75 for defensive pattern
                relevant_section = '\n'.join(lines[59:75])  # 0-indexed, so line 67 is index 66
                
                has_fix_in_location = any(re.search(pattern, relevant_section) for pattern in defensive_patterns)
                
                if has_fix_in_location:
                    criteria_passed += 1
                    feedback_parts.append("✅ Fix located near line 67 (correct location)")
                else:
                    feedback_parts.append("❌ Fix not found near line 67 (should be where address_info is used)")
            else:
                feedback_parts.append(f"❌ File appears truncated ({len(lines)} lines, expected >67)")
        else:
            feedback_parts.append("❌ Cannot check fix location (file not found)")
        
        # Criterion 7: Investigation proposes a solution
        if notes_exists:
            fix_keywords = ['fix', 'solution', 'workaround', 'prevent', 'check', 'validate', 'handle', 'add', 'should']
            has_proposed_fix = any(keyword in notes_content.lower() for keyword in fix_keywords)
            
            if has_proposed_fix:
                criteria_passed += 1
                feedback_parts.append("✅ Investigation proposes a fix/solution")
            else:
                feedback_parts.append("❌ Investigation should propose a fix or workaround")
        else:
            feedback_parts.append("❌ Cannot check proposed solution (notes not found)")
        
        # Calculate score and determine if passed
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # 6/7 criteria = ~86%
        
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
