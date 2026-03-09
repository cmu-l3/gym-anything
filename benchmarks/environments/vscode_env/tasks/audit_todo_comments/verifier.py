#!/usr/bin/env python3
"""
Verifier for Audit TODO Comments task
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_todo_audit(traj, env_info, task_info):
    """
    Verify that the user successfully audited TODO comments.
    
    Checks:
    1. TODO_AUDIT.md file exists
    2. Contains references to source files
    3. Contains actual TODO markers we planted
    4. Has structure (headers, bullets, line numbers)
    5. BONUS: Check if any TODOs were actually resolved
    
    Returns:
        dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='todo_audit_verify_')
    
    try:
        # Copy TODO_AUDIT.md from container
        audit_file_local = os.path.join(temp_dir, "TODO_AUDIT.md")
        
        try:
            copy_from_env("/tmp/TODO_AUDIT.md", audit_file_local)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"❌ FAILED: Could not find TODO_AUDIT.md. Create a file named TODO_AUDIT.md in the workspace root to document all TODO/FIXME/HACK markers. Error: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(audit_file_local) or os.path.getsize(audit_file_local) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ FAILED: TODO_AUDIT.md is empty or not found. You need to create a markdown file documenting all TODO/FIXME/HACK markers."
            }
        
        # Read the audit file
        try:
            audit_content = read_file_content(audit_file_local)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ FAILED: Could not read TODO_AUDIT.md: {str(e)}"
            }
        
        if len(audit_content.strip()) < 50:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ FAILED: TODO_AUDIT.md is too short. Document the TODO markers found in the codebase."
            }
        
        # Known TODO markers we planted (key phrases from comments)
        expected_markers = {
            "auth.py": [
                "rate limiting",
                "md5",
                "sql injection",
                "session token",
                "unit tests"
            ],
            "middleware.py": [
                "cors",
                "www-authenticate",
                "bearer token",
                "logging"
            ],
            "config.py": [
                "environment variables",
                "configuration validation",
                "multiple environments"
            ],
            "test_auth.py": [
                "rate limiting",
                "password complexity",
                "token expiration"
            ],
            "readme": [
                "installation",
                "test coverage"
            ]
        }
        
        score = 0.0
        feedback_parts = []
        metadata = {}
        
        audit_lower = audit_content.lower()
        
        # Criterion 1: File exists (already checked)
        feedback_parts.append("✅ TODO_AUDIT.md file created")
        score += 0.2
        
        # Criterion 2: Contains file references
        file_references = 0
        for filename in expected_markers.keys():
            if filename.lower() in audit_lower:
                file_references += 1
        
        if file_references < 2:
            feedback_parts.append(f"⚠️ Only found {file_references} file references. Search across all Python files.")
            score += 0.05
        elif file_references < 3:
            feedback_parts.append(f"✅ Found {file_references} file references (adequate)")
            score += 0.15
        else:
            feedback_parts.append(f"✅ Found {file_references} file references (excellent)")
            score += 0.2
        
        metadata["files_referenced"] = file_references
        
        # Criterion 3: Contains specific TODO markers we planted
        markers_found = 0
        total_markers = sum(len(markers) for markers in expected_markers.values())
        
        for file, markers in expected_markers.items():
            for marker_phrase in markers:
                # Look for the marker phrase anywhere in the audit
                if marker_phrase.lower() in audit_lower:
                    markers_found += 1
        
        marker_percentage = (markers_found / total_markers) * 100
        metadata["markers_found"] = markers_found
        metadata["total_markers"] = total_markers
        metadata["marker_percentage"] = round(marker_percentage, 1)
        
        if markers_found < 5:
            feedback_parts.append(f"⚠️ Only found {markers_found}/{total_markers} TODO markers ({marker_percentage:.0f}% coverage). Use Find in Files to search comprehensively.")
            score += 0.1
        elif markers_found < 10:
            feedback_parts.append(f"✅ Found {markers_found}/{total_markers} TODO markers ({marker_percentage:.0f}% coverage)")
            score += 0.2
        else:
            feedback_parts.append(f"✅ Found {markers_found}/{total_markers} TODO markers ({marker_percentage:.0f}% coverage - excellent!)")
            score += 0.3
        
        # Criterion 4: Has structure (sections, categories, formatting)
        structure_indicators = [
            (r'^#+\s+\w+', "markdown headers"),
            (r'^\s*[-*+]\s+', "bullet points"),
            (r'\b(critical|high|medium|low|priority)\b', "priority markers"),
            (r':\d+:', "line numbers"),
            (r'(file:|path:|`[\w/.]+`|\*\*[\w/.]+\*\*)', "file path formatting"),
            (r'\d+\.\s+', "numbered lists")
        ]
        
        structure_score = 0
        structure_found = []
        for pattern, name in structure_indicators:
            if re.search(pattern, audit_content, re.MULTILINE | re.IGNORECASE):
                structure_score += 1
                structure_found.append(name)
        
        metadata["structure_elements"] = structure_found
        
        if structure_score < 2:
            feedback_parts.append("⚠️ Audit lacks clear structure. Use headers, bullet points, or categories.")
            score += 0.05
        elif structure_score < 3:
            feedback_parts.append(f"✅ Audit has basic structure ({', '.join(structure_found[:2])})")
            score += 0.1
        else:
            feedback_parts.append(f"✅ Audit has excellent structure ({', '.join(structure_found[:3])})")
            score += 0.15
        
        # Criterion 5: BONUS - Check if any TODOs were actually addressed/removed
        todos_resolved = False
        try:
            # Copy final source files
            auth_final = os.path.join(temp_dir, "auth_final.py")
            middleware_final = os.path.join(temp_dir, "middleware_final.py")
            config_final = os.path.join(temp_dir, "config_final.py")
            
            copy_from_env("/tmp/auth_final.py", auth_final)
            copy_from_env("/tmp/middleware_final.py", middleware_final)
            copy_from_env("/tmp/config_final.py", config_final)
            
            # Original counts of TODO markers we planted
            original_counts = {
                "auth_final.py": 5,
                "middleware_final.py": 4,
                "config_final.py": 4
            }
            
            for filename, original_count in original_counts.items():
                filepath = os.path.join(temp_dir, filename)
                if os.path.exists(filepath):
                    content = read_file_content(filepath)
                    # Count TODO/FIXME/HACK/XXX/NOTE markers
                    current_count = len(re.findall(r'\b(TODO|FIXME|HACK|XXX|NOTE):', content, re.IGNORECASE))
                    
                    if current_count < original_count:
                        todos_resolved = True
                        metadata[f"{filename}_todos_reduced"] = f"{current_count}/{original_count}"
                        break
        except Exception as e:
            logger.debug(f"Could not check for resolved TODOs: {e}")
        
        if todos_resolved:
            feedback_parts.append("🌟 BONUS: You resolved or removed some TODO markers!")
            score += 0.15
        
        # Normalize score to 0-1 range
        score = min(score, 1.0)
        
        # Convert to 0-100 scale
        score_percentage = int(score * 100)
        
        # Determine success threshold (60%)
        success = score >= 0.6
        
        # Compile final feedback
        if success:
            status = "✅ SUCCESS"
            summary = f"You successfully audited the TODO comments with {marker_percentage:.0f}% marker coverage."
        else:
            status = "❌ FAILED"
            summary = (
                "Audit incomplete. To succeed: (1) Create TODO_AUDIT.md, "
                "(2) Use Find in Files (Ctrl+Shift+F) with regex 'TODO|FIXME|HACK|XXX|NOTE' to search all files, "
                "(3) Document findings with file paths and context, "
                "(4) Add structure with markdown headers/bullets."
            )
        
        feedback = f"{status}\n\n{summary}\n\n" + "\n".join(feedback_parts)
        
        return {
            "passed": success,
            "score": score_percentage,
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
        cleanup_verification_temp(temp_dir)
