#!/usr/bin/env python3
"""
Verifier for snapshot_interrupted_context@1

Checks that the agent properly created a context snapshot before switching tasks.
"""

import sys
import os
import logging
import tempfile
import shutil
import json
import re
from pathlib import Path
from typing import Dict, Any, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_context_snapshot(traj, env_info, task_info):
    """
    Verify that proper context snapshot was created.
    
    Checks:
    1. Inline comments added at bug location (line ~26 in payment_processor.py)
    2. TODO marker exists summarizing debugging state
    3. _DEBUG_NOTES.md file exists with proper content
    4. Workspace file was saved
    5. Content quality (actually useful for resuming work)
    
    Returns:
        dict with keys: passed, score, feedback
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Copy function not available"
        }
    
    EXPORT_DIR = "/tmp/task_export_snapshot"
    
    # Create temp directory for verification
    temp_dir = tempfile.mkdtemp(prefix='verify_snapshot_')
    
    try:
        # Copy exported files from container
        local_payment = os.path.join(temp_dir, "payment_processor.py")
        local_notes = os.path.join(temp_dir, "_DEBUG_NOTES.md")
        local_workspace = os.path.join(temp_dir, "workspace.code-workspace")
        local_test = os.path.join(temp_dir, "test_payment.py")
        
        # Copy files
        files_copied = {}
        try:
            copy_from_env(f"{EXPORT_DIR}/payment_processor.py", local_payment)
            files_copied['payment_processor'] = os.path.exists(local_payment) and os.path.getsize(local_payment) > 0
        except Exception as e:
            logger.warning(f"Failed to copy payment_processor.py: {e}")
            files_copied['payment_processor'] = False
        
        try:
            copy_from_env(f"{EXPORT_DIR}/_DEBUG_NOTES.md", local_notes)
            files_copied['notes'] = os.path.exists(local_notes) and os.path.getsize(local_notes) > 0
        except Exception as e:
            logger.warning(f"Failed to copy _DEBUG_NOTES.md: {e}")
            files_copied['notes'] = False
        
        try:
            copy_from_env(f"{EXPORT_DIR}/workspace.code-workspace", local_workspace)
            files_copied['workspace'] = os.path.exists(local_workspace) and os.path.getsize(local_workspace) > 10
        except Exception as e:
            logger.warning(f"Failed to copy workspace file: {e}")
            files_copied['workspace'] = False
        
        try:
            copy_from_env(f"{EXPORT_DIR}/test_payment.py", local_test)
            files_copied['test'] = os.path.exists(local_test) and os.path.getsize(local_test) > 0
        except Exception as e:
            logger.warning(f"Failed to copy test_payment.py: {e}")
            files_copied['test'] = False
        
        if not files_copied['payment_processor']:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ payment_processor.py file not found or empty"
            }
        
        feedback_parts = []
        points = 0.0
        max_points = 5.0
        metadata = {}
        
        # ===== CHECK 1: Inline context comments at bug location =====
        try:
            payment_content = read_file_content(local_payment)
            lines = payment_content.split('\n')
            
            # Find the bug line (contains "amount": amount and is around line 26)
            bug_line_idx = None
            for idx, line in enumerate(lines):
                # Look for the specific line with the bug
                if '"amount": amount' in line and 'transaction_data' in lines[max(0, idx-2):idx+3]:
                    bug_line_idx = idx
                    break
            
            if bug_line_idx is None:
                # Try to find it more loosely
                for idx, line in enumerate(lines):
                    if '"amount"' in line and 'amount' in line and idx > 20 and idx < 35:
                        bug_line_idx = idx
                        break
            
            if bug_line_idx is None:
                feedback_parts.append("⚠️ Could not locate bug line in payment_processor.py")
                metadata['bug_line_found'] = False
            else:
                # Check ±5 lines around bug for context comments
                context_comment_found = False
                comment_quality = ""
                comment_line = ""
                
                for offset in range(-5, 6):
                    check_idx = bug_line_idx + offset
                    if 0 <= check_idx < len(lines):
                        line = lines[check_idx]
                        # Look for various comment patterns
                        if any(marker in line.upper() for marker in ['CONTEXT:', 'BUG:', 'TODO:', 'INVESTIGATING:', 'NOTE:', 'FIXME:', 'HYPOTHESIS:', 'NEXT:']):
                            context_comment_found = True
                            comment_quality = line.strip()
                            comment_line = line
                            break
                        # Also accept substantial comments near the bug line (even without markers)
                        elif '#' in line and len(line.strip()) > 30 and check_idx >= bug_line_idx - 2 and check_idx <= bug_line_idx + 2:
                            context_comment_found = True
                            comment_quality = line.strip()
                            comment_line = line
                            break
                
                if context_comment_found:
                    # Check comment quality - should mention the investigation
                    quality_keywords = [
                        'float', 'decimal', 'precision', 'investigating', 'suspect', 'bug', 
                        'fix', 'test', 'hypothesis', 'issue', 'problem', '10.10', '10.09',
                        'amount', 'money', 'currency', 'ieee', 'rounding'
                    ]
                    comment_lower = comment_quality.lower()
                    keyword_matches = sum(1 for kw in quality_keywords if kw in comment_lower)
                    has_quality = keyword_matches >= 2
                    
                    if has_quality:
                        points += 1.5
                        feedback_parts.append(f"✅ High-quality inline context comment found near line {bug_line_idx + 1}")
                        metadata['inline_comment'] = comment_quality[:100]
                        metadata['inline_comment_quality'] = 'high'
                    else:
                        points += 0.5
                        feedback_parts.append(f"⚠️ Inline comment exists but lacks detail near line {bug_line_idx + 1}")
                        metadata['inline_comment'] = comment_quality[:100]
                        metadata['inline_comment_quality'] = 'low'
                else:
                    feedback_parts.append(f"❌ No context comment found near bug location (line {bug_line_idx + 1})")
                    metadata['inline_comment'] = None
        
        except Exception as e:
            feedback_parts.append(f"❌ Error checking payment_processor.py: {e}")
            logger.error(f"Error in check 1: {e}", exc_info=True)
        
        # ===== CHECK 2: TODO marker summarizing debugging state =====
        try:
            # Look for TODO near top of file (first 40 lines to be more lenient)
            todo_found = False
            todo_content = ""
            
            for i, line in enumerate(lines[:40]):
                if any(marker in line.upper() for marker in ['TODO:', 'FIXME:', 'NOTE:', 'DEBUGGING:']):
                    todo_found = True
                    todo_content = line.strip()
                    break
            
            if todo_found:
                # Check if TODO mentions the debugging context
                context_keywords = [
                    'payment', 'amount', 'float', 'precision', 'debug', 'bug', 'fix',
                    'investigating', 'issue', 'problem', '10.10', 'decimal', 'money'
                ]
                todo_lower = todo_content.lower()
                has_context = sum(1 for kw in context_keywords if kw in todo_lower) >= 2
                
                if has_context:
                    points += 1.0
                    feedback_parts.append(f"✅ TODO marker with debugging context found")
                    metadata['todo_marker'] = todo_content[:100]
                    metadata['todo_quality'] = 'high'
                else:
                    points += 0.3
                    feedback_parts.append(f"⚠️ TODO exists but lacks debugging context")
                    metadata['todo_marker'] = todo_content[:100]
                    metadata['todo_quality'] = 'low'
            else:
                feedback_parts.append("❌ No TODO marker found in first 40 lines")
                metadata['todo_marker'] = None
        
        except Exception as e:
            feedback_parts.append(f"❌ Error checking for TODO markers: {e}")
            logger.error(f"Error in check 2: {e}", exc_info=True)
        
        # ===== CHECK 3: _DEBUG_NOTES.md file with proper content =====
        try:
            if not files_copied['notes']:
                feedback_parts.append("❌ _DEBUG_NOTES.md file not found")
                metadata['notes_created'] = False
            else:
                notes_content = read_file_content(local_notes)
                
                if len(notes_content.strip()) == 0:
                    feedback_parts.append("❌ _DEBUG_NOTES.md is empty")
                    metadata['notes_created'] = True
                    metadata['notes_quality'] = 'empty'
                else:
                    metadata['notes_length'] = len(notes_content)
                    metadata['notes_created'] = True
                    
                    # Check for required elements
                    notes_lower = notes_content.lower()
                    
                    # Timestamp (various formats)
                    has_timestamp = bool(re.search(r'\d{4}-\d{2}-\d{2}|\d{1,2}:\d{2}|timestamp|time|date', notes_lower))
                    
                    # Working on / investigating
                    has_working_on = any(kw in notes_lower for kw in 
                                       ['working on', 'investigating', 'debugging', 'analyzing', 'bug', 'issue', 'problem'])
                    
                    # Hypothesis / suspicion
                    has_hypothesis = any(kw in notes_lower for kw in 
                                        ['float', 'decimal', 'precision', 'suspect', 'hypothesis', 
                                         'cause', 'reason', 'issue', 'ieee', '10.10', 'amount'])
                    
                    # Next steps
                    has_next_steps = any(kw in notes_lower for kw in 
                                        ['next', 'todo', 'need to', 'should', 'plan', 'step', 
                                         'action', 'fix', 'test', 'change', 'refactor'])
                    
                    score_elements = sum([has_timestamp, has_working_on, has_hypothesis, has_next_steps])
                    
                    if score_elements >= 3:
                        points += 1.5
                        feedback_parts.append(f"✅ Comprehensive _DEBUG_NOTES.md created ({score_elements}/4 elements)")
                        metadata['notes_quality'] = 'high'
                    elif score_elements >= 2:
                        points += 0.8
                        feedback_parts.append(f"⚠️ _DEBUG_NOTES.md exists but incomplete ({score_elements}/4 elements)")
                        metadata['notes_quality'] = 'medium'
                    else:
                        points += 0.3
                        feedback_parts.append(f"⚠️ _DEBUG_NOTES.md too sparse ({score_elements}/4 elements)")
                        metadata['notes_quality'] = 'low'
                    
                    metadata['notes_elements'] = {
                        'timestamp': has_timestamp,
                        'working_on': has_working_on,
                        'hypothesis': has_hypothesis,
                        'next_steps': has_next_steps
                    }
        
        except Exception as e:
            feedback_parts.append(f"❌ Error checking _DEBUG_NOTES.md: {e}")
            logger.error(f"Error in check 3: {e}", exc_info=True)
        
        # ===== CHECK 4: Workspace file saved =====
        try:
            if not files_copied['workspace']:
                feedback_parts.append("❌ Workspace file not saved")
                metadata['workspace_saved'] = False
            else:
                try:
                    workspace_content = read_file_content(local_workspace)
                    
                    # Try to parse as JSON
                    workspace_data = json.loads(workspace_content)
                    
                    # Check that workspace contains project_alpha folder
                    folders = workspace_data.get('folders', [])
                    
                    # Folders can be list of strings or list of dicts with 'path' key
                    has_project = False
                    for folder in folders:
                        folder_str = str(folder).lower()
                        if 'project_alpha' in folder_str or 'project-alpha' in folder_str:
                            has_project = True
                            break
                    
                    if has_project:
                        points += 1.0
                        feedback_parts.append("✅ Workspace file saved with correct project configuration")
                        metadata['workspace_saved'] = True
                        metadata['workspace_valid'] = True
                    else:
                        points += 0.3
                        feedback_parts.append("⚠️ Workspace file exists but may not contain project_alpha")
                        metadata['workspace_saved'] = True
                        metadata['workspace_valid'] = False
                
                except json.JSONDecodeError as je:
                    feedback_parts.append("⚠️ Workspace file exists but is not valid JSON")
                    metadata['workspace_saved'] = True
                    metadata['workspace_valid'] = False
                    points += 0.2
        
        except Exception as e:
            feedback_parts.append(f"❌ Error checking workspace file: {e}")
            logger.error(f"Error in check 4: {e}", exc_info=True)
        
        # ===== CALCULATE FINAL RESULT =====
        success = points >= 3.5  # Need at least 70% to pass (3.5/5.0)
        score = int((points / max_points) * 100)
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Score: {points:.1f}/{max_points:.1f} ({score}%)"
        
        if success:
            feedback += "\n\n✅ PASS: Context snapshot successfully created. You can now switch to project_beta and return later without losing your mental state."
        else:
            feedback += "\n\n❌ FAIL: Context snapshot incomplete. Returning to this debugging session later would require significant re-orientation time."
        
        metadata['points'] = points
        metadata['max_points'] = max_points
        
        logger.info(f"Verification complete: passed={success}, score={score}, points={points}/{max_points}")
        
        return {
            "passed": success,
            "score": score,
            "feedback": feedback,
            "metadata": metadata
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
