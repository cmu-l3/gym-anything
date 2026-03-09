#!/usr/bin/env python3
"""
Verifier for Fix Timezone Handling task
"""

import sys
import os
import logging
import tempfile
import re
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_timezone_fixes(traj, env_info, task_info):
    """
    Verify that timezone handling was fixed correctly.
    
    Checks:
    1. Timezone import exists in scheduler.py (0.25 points)
    2. At least 3 timezone-aware datetime.now() calls total (0.40 points)
    3. No naive datetime.now() in critical functions (0.35 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='timezone_verify_')
    
    try:
        # Define file paths
        scheduler_container = "/home/ga/workspace/scheduler_app/scheduler.py"
        models_container = "/home/ga/workspace/scheduler_app/models.py"
        
        scheduler_local = os.path.join(temp_dir, "scheduler.py")
        models_local = os.path.join(temp_dir, "models.py")
        
        # Copy files
        try:
            copy_from_env(scheduler_container, scheduler_local)
            copy_from_env(models_container, models_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy files: {str(e)}"}
        
        if not os.path.exists(scheduler_local):
            return {"passed": False, "score": 0, "feedback": "scheduler.py not found"}
        
        if not os.path.exists(models_local):
            return {"passed": False, "score": 0, "feedback": "models.py not found"}
        
        # Read file contents
        scheduler_content = read_file_content(scheduler_local)
        models_content = read_file_content(models_local)
        
        score = 0.0
        feedback_parts = []
        
        # ========================================
        # Criterion 1: Timezone import exists (25 points)
        # ========================================
        has_timezone_import = bool(
            re.search(r'from\s+datetime\s+import\s+.*timezone', scheduler_content) or
            re.search(r'from\s+datetime\s+import\s+.*timezone', models_content) or
            re.search(r'import\s+.*timezone', scheduler_content) or
            re.search(r'import\s+.*timezone', models_content)
        )
        
        if has_timezone_import:
            score += 25
            feedback_parts.append("✅ Timezone import added")
        else:
            feedback_parts.append("❌ Missing timezone import")
        
        # ========================================
        # Criterion 2: Count timezone-aware datetime.now() usage (40 points)
        # ========================================
        # Pattern: datetime.now(timezone.utc) or datetime.now(tz=timezone.utc) etc.
        utc_now_pattern = r'datetime\.now\s*\(\s*(?:tz\s*=\s*)?timezone\.utc\s*\)'
        
        scheduler_utc_count = len(re.findall(utc_now_pattern, scheduler_content))
        models_utc_count = len(re.findall(utc_now_pattern, models_content))
        total_utc_count = scheduler_utc_count + models_utc_count
        
        if total_utc_count >= 4:
            # Excellent: All 4 instances fixed
            score += 40
            feedback_parts.append(f"✅ Found {total_utc_count} timezone-aware datetime.now() calls (excellent!)")
        elif total_utc_count >= 3:
            # Good: At least 3 instances fixed
            score += 40
            feedback_parts.append(f"✅ Found {total_utc_count} timezone-aware datetime.now() calls")
        elif total_utc_count >= 2:
            # Partial: 2 instances fixed
            score += 25
            feedback_parts.append(f"⚠️ Found only {total_utc_count} timezone-aware calls (expected 3+)")
        elif total_utc_count >= 1:
            # Minimal: 1 instance fixed
            score += 10
            feedback_parts.append(f"⚠️ Found only {total_utc_count} timezone-aware call (expected 3+)")
        else:
            feedback_parts.append("❌ No timezone-aware datetime.now() calls found")
        
        # ========================================
        # Criterion 3: No naive datetime.now() in critical functions (35 points)
        # ========================================
        critical_functions = [
            'create_appointment',
            'get_upcoming_appointments',
            'save_appointment'
        ]
        
        naive_in_critical = []
        combined_content = scheduler_content + "\n\n### MODELS FILE ###\n\n" + models_content
        
        for func_name in critical_functions:
            # Extract function body using regex
            # Pattern: def func_name(...): followed by indented content until next def/class or EOF
            func_pattern = rf'def\s+{func_name}\s*\([^)]*\)\s*:.*?(?=\ndef\s|\nclass\s|\Z)'
            func_match = re.search(func_pattern, combined_content, re.DOTALL)
            
            if func_match:
                func_body = func_match.group(0)
                # Check for naive datetime.now() - should match datetime.now() but NOT datetime.now(timezone.utc)
                # Look for datetime.now() followed by empty parens
                naive_pattern = r'datetime\.now\s*\(\s*\)'
                if re.search(naive_pattern, func_body):
                    naive_in_critical.append(func_name)
        
        if len(naive_in_critical) == 0:
            score += 35
            feedback_parts.append("✅ No naive datetime.now() in critical functions")
        elif len(naive_in_critical) == 1:
            score += 20
            feedback_parts.append(f"⚠️ Still has naive datetime.now() in: {naive_in_critical[0]}")
        else:
            feedback_parts.append(f"❌ Naive datetime.now() still in: {', '.join(naive_in_critical)}")
        
        # ========================================
        # Calculate final result
        # ========================================
        passed = score >= 75
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
