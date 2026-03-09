#!/usr/bin/env python3
"""
Verifier for Extract from Massive Log task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    parse_vscode_settings,
    read_file_content,
    check_file_exists
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_log_extraction(traj, env_info, task_info):
    """
    Verify that the log extraction task was completed correctly.
    
    Checks:
    1. VSCode configured for large files (30%)
    2. Extracted file exists with correct errors (40%)
    3. File size optimized (10%)
    4. CLI tool usage evidence (20%)
    
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='log_extract_verify_')
    
    try:
        score = 0.0
        feedback_parts = []
        
        # ===== 1. Check VSCode Settings Configuration (30%) =====
        logger.info("Checking VSCode settings configuration...")
        
        user_settings_local = os.path.join(temp_dir, "user_settings.json")
        workspace_settings_local = os.path.join(temp_dir, "workspace_settings.json")
        
        try:
            copy_from_env("/tmp/vscode_settings/user_settings.json", user_settings_local)
            copy_from_env("/tmp/vscode_settings/workspace_settings.json", workspace_settings_local)
        except Exception as e:
            logger.warning(f"Could not copy settings files: {e}")
            feedback_parts.append("⚠️ Could not access settings files")
        
        max_memory = 0
        settings_location = None
        
        # Check workspace settings first (higher priority)
        if os.path.exists(workspace_settings_local) and os.path.getsize(workspace_settings_local) > 2:
            ws_settings = parse_vscode_settings(workspace_settings_local)
            ws_memory = ws_settings.get("files.maxMemoryForLargeFilesMB", 0)
            if ws_memory > max_memory:
                max_memory = ws_memory
                settings_location = "workspace"
        
        # Check user settings
        if os.path.exists(user_settings_local) and os.path.getsize(user_settings_local) > 2:
            user_settings = parse_vscode_settings(user_settings_local)
            user_memory = user_settings.get("files.maxMemoryForLargeFilesMB", 0)
            if user_memory > max_memory:
                max_memory = user_memory
                settings_location = "user"
        
        if max_memory >= 1024:
            score += 0.30
            feedback_parts.append(f"✅ Large file memory configured: {max_memory}MB ({settings_location} settings)")
        elif max_memory > 0:
            score += 0.15
            feedback_parts.append(f"⚠️ Partial: Large file memory set to {max_memory}MB (need >= 1024MB)")
        else:
            feedback_parts.append("❌ Large file memory not configured (needed: files.maxMemoryForLargeFilesMB >= 1024)")
        
        # ===== 2. Check Extracted File Exists and Quality (50% total) =====
        logger.info("Checking extracted file...")
        
        extracted_file_local = os.path.join(temp_dir, "payment_failures.log")
        
        try:
            copy_from_env("/tmp/payment_failures.log", extracted_file_local)
        except Exception as e:
            logger.error(f"Could not copy extracted file: {e}")
            feedback_parts.append("❌ Extracted file 'payment_failures.log' not found")
            return {
                "passed": False,
                "score": round(score * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(extracted_file_local) or os.path.getsize(extracted_file_local) < 10:
            feedback_parts.append("❌ Extracted file not found or empty")
            return {
                "passed": False,
                "score": round(score * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # File exists
        score += 0.10
        feedback_parts.append("✅ Extracted file created")
        
        # Check content quality
        content = read_file_content(extracted_file_local)
        
        if not content:
            feedback_parts.append("❌ Extracted file is empty")
            return {
                "passed": False,
                "score": round(score * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Count critical errors
        error_pattern = "CRITICAL: Payment gateway timeout - transaction failed"
        error_count = content.count(error_pattern)
        
        expected_min = 28  # Allow some tolerance (34 ± 6)
        expected_max = 40
        
        if expected_min <= error_count <= expected_max:
            score += 0.30
            feedback_parts.append(f"✅ All critical errors extracted: {error_count} errors found")
        elif error_count > 0:
            score += 0.15
            if error_count < expected_min:
                feedback_parts.append(f"⚠️ Incomplete extraction: {error_count} errors (expected ~34)")
            else:
                feedback_parts.append(f"⚠️ Too many errors: {error_count} (possible duplicates?)")
        else:
            feedback_parts.append("❌ No critical errors found in extracted file")
        
        # Check for context (lines should have surrounding log entries)
        lines = content.split('\n')
        has_context = False
        context_count = 0
        
        for i, line in enumerate(lines):
            if error_pattern in line:
                # Check if there are lines before and after (context)
                before_ok = i > 0 and lines[i-1].strip() and "payment-gateway-api" in lines[i-1]
                after_ok = i < len(lines) - 1 and lines[i+1].strip() and "payment-gateway-api" in lines[i+1]
                
                if before_ok and after_ok:
                    has_context = True
                    context_count += 1
        
        if has_context and context_count >= error_count * 0.7:  # At least 70% have context
            score += 0.10
            feedback_parts.append("✅ Context lines included with errors")
        elif has_context:
            score += 0.05
            feedback_parts.append("⚠️ Partial context included")
        else:
            feedback_parts.append("❌ Context lines missing (need -B 2 -A 2)")
        
        # ===== 3. Check File Size Optimization (10%) =====
        logger.info("Checking file size...")
        
        try:
            file_size_bytes = os.path.getsize(extracted_file_local)
            file_size_kb = file_size_bytes / 1024
            
            if file_size_kb < 500:
                score += 0.10
                feedback_parts.append(f"✅ File size optimized: {file_size_kb:.1f} KB")
            elif file_size_kb < 2048:  # Less than 2MB
                score += 0.05
                feedback_parts.append(f"⚠️ File larger than ideal: {file_size_kb:.1f} KB (but acceptable)")
            else:
                feedback_parts.append(f"❌ Extracted file too large: {file_size_kb:.1f} KB (possible over-extraction)")
        except Exception as e:
            logger.warning(f"Could not check file size: {e}")
        
        # ===== 4. Check Terminal Tool Usage (20%) =====
        logger.info("Checking CLI tool usage...")
        
        bash_history_local = os.path.join(temp_dir, "bash_history.txt")
        
        try:
            copy_from_env("/tmp/bash_history.txt", bash_history_local)
        except Exception as e:
            logger.warning(f"Could not copy bash history: {e}")
        
        if os.path.exists(bash_history_local) and os.path.getsize(bash_history_local) > 0:
            history = read_file_content(bash_history_local)
            
            # Check for evidence of CLI tools usage
            used_grep = "grep" in history
            has_context_flags = any(flag in history for flag in ["-A", "-B", "-C", "context"])
            has_output_redirect = ">" in history or "payment_failures" in history
            
            if used_grep and has_context_flags and has_output_redirect:
                score += 0.20
                feedback_parts.append("✅ CLI tools used correctly (grep with context flags and output redirect)")
            elif used_grep and has_context_flags:
                score += 0.15
                feedback_parts.append("⚠️ CLI tools used but output redirect unclear")
            elif used_grep:
                score += 0.10
                feedback_parts.append("⚠️ grep used but may lack context extraction flags")
            else:
                # Check if awk/sed/other tools were used
                other_tools = any(tool in history for tool in ["awk", "sed", "cat", "tail"])
                if other_tools:
                    score += 0.10
                    feedback_parts.append("⚠️ Alternative CLI tools used (not grep)")
                else:
                    feedback_parts.append("❌ No clear evidence of CLI tool usage in bash history")
        else:
            feedback_parts.append("⚠️ Cannot verify tool usage (bash history unavailable)")
        
        # ===== Final Evaluation =====
        score = min(score, 1.0)  # Cap at 100%
        score_pct = round(score * 100)
        passed = score >= 0.80  # 80% threshold
        
        if score >= 0.90:
            status = "✅ EXCELLENT"
        elif score >= 0.80:
            status = "✅ PASS"
        elif score >= 0.60:
            status = "⚠️ PARTIAL"
        else:
            status = "❌ INSUFFICIENT"
        
        feedback = f"{status} (Score: {score_pct}%) - " + " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {status}, Score: {score_pct}%")
        
        return {
            "passed": passed,
            "score": score_pct,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Clean up temp directory
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
