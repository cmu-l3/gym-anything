#!/usr/bin/env python3
"""
Verifier for Profile Slow Endpoint task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_profiling_task(traj, env_info, task_info):
    """
    Verify that the profiling task was completed correctly.
    
    Checks:
    1. profile_results.txt exists and contains profiling data (25 points)
    2. PERFORMANCE.md exists with sufficient content (25 points)
    3. Correct bottleneck identified in documentation (30 points)
    4. TODO comment added to external_api.py near the bottleneck (20 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='profile_verify_')
    
    try:
        workspace_base = "/home/ga/workspace"
        score = 0
        feedback_parts = []
        
        # ============================================================
        # Check 1: profile_results.txt exists and contains profiling data
        # ============================================================
        profile_file = os.path.join(temp_dir, "profile_results.txt")
        try:
            copy_from_env(f"{workspace_base}/profile_results.txt", profile_file)
        except Exception as e:
            feedback_parts.append(f"❌ profile_results.txt not found. Did you run 'python tests/test_performance.py'? Error: {str(e)}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(profile_file) or os.path.getsize(profile_file) == 0:
            feedback_parts.append("❌ profile_results.txt is empty or not found")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        with open(profile_file, 'r', encoding='utf-8', errors='ignore') as f:
            profile_content = f.read()
        
        # Check if it contains profiling data
        if "enrich_customer_data" not in profile_content or "external_api" not in profile_content:
            feedback_parts.append("❌ profile_results.txt doesn't contain expected profiling data for enrich_customer_data")
            return {
                "passed": False,
                "score": 5,
                "feedback": " | ".join(feedback_parts)
            }
        
        score += 25
        feedback_parts.append("✅ Profiling script executed successfully (profile_results.txt found)")
        
        # ============================================================
        # Check 2: PERFORMANCE.md exists and has content
        # ============================================================
        perf_doc_file = os.path.join(temp_dir, "PERFORMANCE.md")
        try:
            copy_from_env(f"{workspace_base}/PERFORMANCE.md", perf_doc_file)
        except Exception as e:
            feedback_parts.append(f"❌ PERFORMANCE.md not found. Error: {str(e)}")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(perf_doc_file):
            feedback_parts.append("❌ PERFORMANCE.md not found")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        with open(perf_doc_file, 'r', encoding='utf-8', errors='ignore') as f:
            perf_content = f.read()
        
        if len(perf_content.strip()) < 80:
            feedback_parts.append("❌ PERFORMANCE.md is too short or empty. Please document your findings.")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        score += 25
        feedback_parts.append("✅ PERFORMANCE.md created with content")
        
        # ============================================================
        # Check 3: Correct bottleneck identified
        # ============================================================
        perf_lower = perf_content.lower()
        
        # Check for key terms that should be in the documentation
        has_function_name = "enrich_customer_data" in perf_lower or "enrich customer data" in perf_lower
        has_file_reference = "external_api" in perf_lower or "external api" in perf_lower
        
        if not has_function_name:
            feedback_parts.append("❌ PERFORMANCE.md doesn't identify 'enrich_customer_data' as the bottleneck")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not has_file_reference:
            feedback_parts.append("⚠️ PERFORMANCE.md should mention 'external_api.py' file")
            score += 15  # Partial credit
        else:
            score += 30
            feedback_parts.append("✅ Correct bottleneck identified (enrich_customer_data in external_api.py)")
        
        # ============================================================
        # Check 4: TODO comment added to external_api.py
        # ============================================================
        api_file = os.path.join(temp_dir, "external_api.py")
        try:
            copy_from_env(f"{workspace_base}/src/utils/external_api.py", api_file)
        except Exception as e:
            feedback_parts.append(f"❌ Could not read external_api.py. Error: {str(e)}")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(api_file):
            feedback_parts.append("❌ src/utils/external_api.py not found")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        with open(api_file, 'r', encoding='utf-8', errors='ignore') as f:
            api_content = f.read()
        
        # Check if TODO comment exists
        if "TODO" not in api_content.upper() and "FIXME" not in api_content.upper():
            feedback_parts.append("❌ No TODO comment added to external_api.py")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Verify TODO is near the bottleneck (time.sleep line)
        lines = api_content.split('\n')
        todo_line_idx = -1
        sleep_line_idx = -1
        
        for i, line in enumerate(lines):
            if "TODO" in line.upper() or "FIXME" in line.upper():
                todo_line_idx = i
            if "time.sleep" in line:
                sleep_line_idx = i
        
        if todo_line_idx == -1:
            feedback_parts.append("❌ TODO comment not found in external_api.py")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        if sleep_line_idx == -1:
            feedback_parts.append("⚠️ Warning: time.sleep line not found (file may have been modified)")
            score += 10  # Partial credit if they found another way
            feedback_parts.append("✅ TODO comment added to external_api.py")
        elif abs(todo_line_idx - sleep_line_idx) > 5:
            feedback_parts.append("⚠️ TODO comment found but not close to the bottleneck code")
            score += 10  # Partial credit
        else:
            score += 20
            feedback_parts.append("✅ TODO comment correctly placed near bottleneck code")
        
        # ============================================================
        # Final scoring
        # ============================================================
        passed = score >= 95
        
        if passed:
            feedback_parts.append("🎉 Task completed successfully! You've identified and documented the performance bottleneck.")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
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
