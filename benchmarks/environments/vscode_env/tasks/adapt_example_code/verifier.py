#!/usr/bin/env python3
"""
Verifier for Adapt Example Code task
Checks if documentation example was properly adapted into the codebase
"""

import sys
import os
import ast
import logging
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adaptation(traj, env_info, task_info):
    """
    Verify the example code adaptation task.
    
    Checks:
    1. FileValidator class exists and is modified
    2. validate() method properly implemented
    3. Validation checks from example are present (size, MIME, extension)
    4. get_validation_errors() method implemented
    5. Error tracking mechanism exists
    6. Code adapted from FastAPI (no FastAPI imports, uses Path)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    validator_path = "/home/ga/workspace/datavalidator/pipeline/validator.py"
    temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False)
    
    try:
        # Copy the validator file from container
        copy_from_env(validator_path, temp_file.name)
    except Exception as e:
        logger.error(f"Failed to copy {validator_path}: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to access validator.py: {str(e)}"}
    
    try:
        content = read_file_content(temp_file.name)
        
        if not content or len(content) < 100:
            return {"passed": False, "score": 0, "feedback": "validator.py appears empty or minimal"}
        
        # Parse the Python file
        try:
            tree = ast.parse(content)
        except SyntaxError as e:
            return {"passed": False, "score": 0, "feedback": f"Syntax error in validator.py: {str(e)}"}
        
        score = 0
        max_score = 100
        feedback_parts = []
        
        # Check 1: FileValidator class exists (20 points)
        validator_class = None
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == 'FileValidator':
                validator_class = node
                break
        
        if not validator_class:
            feedback_parts.append("❌ FileValidator class not found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
        score += 20
        feedback_parts.append("✅ FileValidator class exists")
        
        # Check 2: validate() method properly implemented (25 points)
        validate_method = None
        validate_method_body = ""
        
        for node in validator_class.body:
            if isinstance(node, ast.FunctionDef) and node.name == 'validate':
                validate_method = node
                try:
                    validate_method_body = ast.get_source_segment(content, validate_method) or ""
                except:
                    # Fallback for older Python versions
                    validate_method_body = content
                break
        
        if not validate_method:
            feedback_parts.append("❌ validate() method not found")
        else:
            # Check if method has substantial implementation
            has_todo = 'TODO' in validate_method_body
            is_substantial = len(validate_method_body) > 200
            has_trivial_return = validate_method_body.count('return False') > 0 and len(validate_method_body) < 150
            
            if is_substantial and not has_trivial_return:
                score += 20
                feedback_parts.append("✅ validate() method has substantial implementation")
            elif not has_todo:
                score += 10
                feedback_parts.append("⚠️ validate() method exists but seems minimal")
            else:
                score += 5
                feedback_parts.append("⚠️ validate() method still contains TODO")
        
        # Check 3: Validation checks from example (30 points - 10 each)
        content_lower = content.lower()
        
        # Size check
        has_size_check = any(keyword in content for keyword in ['size', 'seek', 'tell', 'getsize', 'stat'])
        if has_size_check:
            score += 10
            feedback_parts.append("✅ File size validation detected")
        else:
            feedback_parts.append("❌ File size validation not found")
        
        # MIME type check
        has_mime_check = any(keyword in content_lower for keyword in ['mime', 'magic', 'from_buffer', 'from_file'])
        if has_mime_check:
            score += 10
            feedback_parts.append("✅ MIME type validation detected")
        else:
            feedback_parts.append("❌ MIME type validation not found")
        
        # Extension check
        has_extension_check = any(keyword in content_lower for keyword in ['extension', '.json', '.csv', '.txt', 'endswith', 'suffix'])
        if has_extension_check:
            score += 10
            feedback_parts.append("✅ File extension validation detected")
        else:
            feedback_parts.append("❌ File extension validation not found")
        
        # Check 4: get_validation_errors() implemented (15 points)
        get_errors_method = None
        get_errors_body = ""
        
        for node in validator_class.body:
            if isinstance(node, ast.FunctionDef) and node.name == 'get_validation_errors':
                get_errors_method = node
                try:
                    get_errors_body = ast.get_source_segment(content, get_errors_method) or ""
                except:
                    get_errors_body = content
                break
        
        if get_errors_method:
            has_todo = 'TODO' in get_errors_body
            is_substantial = len(get_errors_body) > 50
            
            if is_substantial and not has_todo:
                score += 15
                feedback_parts.append("✅ get_validation_errors() properly implemented")
            elif not has_todo:
                score += 8
                feedback_parts.append("⚠️ get_validation_errors() exists but minimal")
            else:
                score += 3
                feedback_parts.append("⚠️ get_validation_errors() still contains TODO")
        else:
            feedback_parts.append("❌ get_validation_errors() not modified")
        
        # Check 5: Error tracking mechanism (10 points)
        has_error_storage = any(pattern in content for pattern in [
            'self.errors', 'self.validation_errors', 'self._errors',
            'self.error_list', 'self.last_errors'
        ])
        
        if has_error_storage:
            score += 10
            feedback_parts.append("✅ Error tracking mechanism found")
        else:
            feedback_parts.append("⚠️ No clear error storage mechanism (self.errors)")
        
        # Check 6: Adapted from FastAPI (no FastAPI, uses Path) (bonus - informational)
        has_fastapi = any(keyword in content_lower for keyword in ['fastapi', 'uploadfile', '@app', 'httpexception'])
        uses_path = 'Path' in content or 'filepath' in content
        
        if not has_fastapi and uses_path:
            feedback_parts.append("✅ Code adapted from FastAPI to Path-based")
        elif has_fastapi:
            feedback_parts.append("⚠️ Still contains FastAPI references")
        
        # Normalize score
        normalized_score = min(score / max_score, 1.0)
        passed = score >= 70  # 70% threshold
        
        feedback = " | ".join(feedback_parts)
        summary = f"Adaptation score: {score}/{max_score} ({normalized_score*100:.0f}%)"
        
        return {
            "passed": passed,
            "score": int(normalized_score * 100),
            "feedback": f"{summary} | {feedback}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
