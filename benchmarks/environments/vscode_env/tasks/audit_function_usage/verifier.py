#!/usr/bin/env python3
"""
Verifier for Audit Function Usage task (audit_function_usage@1)
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


def verify_function_audit(traj, env_info, task_info):
    """
    Verify that function usage audit was completed correctly.
    
    Checks:
    1. REFACTOR_PLAN.md exists and has substantial content (>200 bytes) - 1.0 point
    2. Documentation mentions at least 4 expected files - 1.5 points
    3. Contains line numbers or location markers - 0.5 points
    4. Mentions 'calculate_discount' at least 4 times - 0.5 points
    5. calculator.py has refactoring comment above function - 2.0 points
    6. Comment mentions refactoring context - included in point 5
    
    Total: 6.0 points
    Pass threshold: 5.5/6.0 (91%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='audit_verify_')
    
    try:
        # Copy exported files from /tmp
        refactor_plan_tmp = "/tmp/refactor_plan.md"
        calculator_tmp = "/tmp/calculator.py"
        
        local_plan = os.path.join(temp_dir, "REFACTOR_PLAN.md")
        local_calculator = os.path.join(temp_dir, "calculator.py")
        
        # Attempt to copy files
        try:
            copy_from_env(refactor_plan_tmp, local_plan)
        except Exception as e:
            logger.warning(f"Failed to copy REFACTOR_PLAN.md: {e}")
        
        try:
            copy_from_env(calculator_tmp, local_calculator)
        except Exception as e:
            logger.warning(f"Failed to copy calculator.py: {e}")
        
        feedback_parts = []
        score = 0.0
        max_score = 6.0
        
        # ===== Check 1: REFACTOR_PLAN.md exists and is substantial =====
        if not os.path.exists(local_plan):
            feedback_parts.append("❌ REFACTOR_PLAN.md does not exist")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        feedback_parts.append("✅ REFACTOR_PLAN.md exists")
        score += 1.0
        
        # Read the refactor plan content
        try:
            with open(local_plan, 'r', encoding='utf-8', errors='ignore') as f:
                plan_content = f.read()
        except Exception as e:
            feedback_parts.append(f"❌ Could not read REFACTOR_PLAN.md: {e}")
            return {
                "passed": False,
                "score": score / max_score * 100,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check if file is substantial (>200 bytes)
        plan_size = len(plan_content)
        if plan_size < 200:
            feedback_parts.append(f"⚠️ REFACTOR_PLAN.md is too short ({plan_size} bytes, expected >200)")
        else:
            feedback_parts.append(f"✅ REFACTOR_PLAN.md has substantial content ({plan_size} bytes)")
            score += 0.5
        
        # ===== Check 2: Mentions at least 4 usage locations =====
        expected_files = ['checkout.py', 'cart.py', 'discount_api.py', 'test_pricing.py']
        mentioned_files = [f for f in expected_files if f in plan_content]
        
        if len(mentioned_files) < 4:
            feedback_parts.append(f"❌ Only {len(mentioned_files)}/4 expected files mentioned: {mentioned_files}")
        else:
            feedback_parts.append(f"✅ All {len(mentioned_files)} usage locations documented: {mentioned_files}")
            score += 1.5
        
        # ===== Check 3: Contains line numbers or location markers =====
        has_line_numbers = bool(re.search(r'(line|Line|L:|:)\s*\d+', plan_content, re.IGNORECASE))
        if has_line_numbers:
            feedback_parts.append("✅ Line numbers or location markers found")
            score += 0.5
        else:
            feedback_parts.append("⚠️ No line numbers found in documentation")
        
        # ===== Check 4: Mentions the function name multiple times =====
        function_mentions = plan_content.lower().count('calculate_discount')
        if function_mentions >= 4:
            feedback_parts.append(f"✅ Function 'calculate_discount' mentioned {function_mentions} times")
            score += 0.5
        else:
            feedback_parts.append(f"⚠️ Function mentioned only {function_mentions} times (expected ≥4)")
        
        # ===== Check 5 & 6: calculator.py has refactoring comment =====
        if not os.path.exists(local_calculator):
            feedback_parts.append("❌ pricing/calculator.py not found")
            final_score = int((score / max_score) * 100)
            return {
                "passed": False,
                "score": final_score,
                "feedback": " | ".join(feedback_parts)
            }
        
        try:
            with open(local_calculator, 'r', encoding='utf-8', errors='ignore') as f:
                calculator_content = f.read()
                calculator_lines = calculator_content.split('\n')
        except Exception as e:
            feedback_parts.append(f"❌ Could not read calculator.py: {e}")
            final_score = int((score / max_score) * 100)
            return {
                "passed": False,
                "score": final_score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Find the calculate_discount function definition
        func_line_idx = None
        for idx, line in enumerate(calculator_lines):
            if 'def calculate_discount' in line:
                func_line_idx = idx
                break
        
        if func_line_idx is None:
            feedback_parts.append("❌ Could not find 'def calculate_discount' in calculator.py")
            final_score = int((score / max_score) * 100)
            return {
                "passed": False,
                "score": final_score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check 5 lines above the function definition for refactor comment
        search_start = max(0, func_line_idx - 5)
        search_lines = calculator_lines[search_start:func_line_idx + 1]
        search_text = '\n'.join(search_lines)
        
        # Must contain a comment with REFACTOR/TODO/PLANNED
        has_marker = bool(re.search(r'#\s*(TODO|REFACTOR|PLANNED)', search_text, re.IGNORECASE))
        
        # Must mention plan/audit/usage/parameter/promo
        has_context = bool(re.search(r'(plan|audit|usage|parameter|promo)', search_text, re.IGNORECASE))
        
        if has_marker and has_context:
            feedback_parts.append("✅ Proper refactoring comment added above function definition")
            score += 2.0
        elif has_marker:
            feedback_parts.append("⚠️ Refactoring marker found but missing context (plan/audit/usage/parameter)")
            score += 1.0
        else:
            feedback_parts.append("❌ No refactoring comment found above calculate_discount function")
        
        # ===== Calculate final score =====
        final_score = int((score / max_score) * 100)
        passed = score >= 5.5  # Must get at least 5.5/6 points (91%)
        
        feedback = " | ".join(feedback_parts)
        feedback += f" | 📊 Score: {score:.1f}/{max_score} ({final_score}%)"
        
        if passed:
            feedback += " | 🎉 Task completed successfully"
        else:
            feedback += " | ❌ Task incomplete"
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
