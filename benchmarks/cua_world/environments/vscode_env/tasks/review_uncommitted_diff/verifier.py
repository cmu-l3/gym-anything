#!/usr/bin/env python3
"""
Verifier for Review Uncommitted Diff task
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_review_uncommitted_diff(traj, env_info, task_info):
    """
    Verify that user reviewed uncommitted changes and removed debug code.
    
    Checks:
    1. All 4 files were reviewed (modification evidence)
    2. Debug code removed (no print/DEBUG statements)
    3. Legitimate changes preserved (fixes, improvements, tests intact)
    4. Review summary document created with required sections
    5. Workflow sequence correct (reasonable timing)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='review_diff_verify_')
    
    try:
        # Copy all exported files from container
        files_to_copy = {
            "orders.py": "/tmp/orders.py",
            "payment.py": "/tmp/payment.py",
            "logger.py": "/tmp/logger.py",
            "test_orders.py": "/tmp/test_orders.py",
            "REVIEW_SUMMARY.md": "/tmp/REVIEW_SUMMARY.md",
            "file_timestamps.txt": "/tmp/file_timestamps.txt"
        }
        
        local_files = {}
        for name, container_path in files_to_copy.items():
            local_path = os.path.join(temp_dir, name)
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[name] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {name}: {e}")
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # ===== CRITERION 1: All 4 files were reviewed (files exist and were modified) =====
        required_files = ["orders.py", "payment.py", "logger.py", "test_orders.py"]
        files_present = sum(1 for f in required_files if f in local_files)
        
        if files_present >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ All {files_present} files present and reviewed")
        else:
            feedback_parts.append(f"❌ Only {files_present}/4 files found")
        
        # ===== CRITERION 2: Debug code removed =====
        debug_patterns = [
            r'print\s*\(\s*["\']DEBUG:',
            r'print\s*\(\s*f["\']DEBUG:',
            r'print\s*\(["\']DEBUG',
            r'TODO:\s*remove',
            r'Hardcoded for testing',
            r'amount\s*=\s*1\.0+\s*#.*[Hh]ardcoded'
        ]
        
        debug_code_found = False
        debug_locations = []
        
        # Check orders.py for debug prints
        if "orders.py" in local_files:
            content = read_file_content(local_files["orders.py"])
            for pattern in debug_patterns:
                if re.search(pattern, content, re.IGNORECASE):
                    debug_code_found = True
                    debug_locations.append(f"orders.py: {pattern[:30]}")
        
        # Check payment.py for debug prints and hardcoded test value
        if "payment.py" in local_files:
            content = read_file_content(local_files["payment.py"])
            
            # Check for debug prints
            for pattern in debug_patterns:
                if re.search(pattern, content, re.IGNORECASE):
                    debug_code_found = True
                    debug_locations.append(f"payment.py: debug print")
            
            # Check for hardcoded test value specifically
            if re.search(r'amount\s*=\s*1\.0+(?:\s*#.*)?', content):
                # Make sure it's the hardcoded line, not the proper one
                lines = content.split('\n')
                for line in lines:
                    if 'amount = 1.0' in line and 'payment_data.get' not in line:
                        debug_code_found = True
                        debug_locations.append("payment.py: hardcoded test value (amount=1.00)")
                        break
        
        if not debug_code_found:
            criteria_passed += 1
            feedback_parts.append("✅ Debug code successfully removed")
        else:
            feedback_parts.append(f"❌ Debug code still present: {'; '.join(debug_locations[:3])}")
        
        # ===== CRITERION 3: Legitimate changes preserved =====
        legitimate_changes_present = 0
        legitimate_issues = []
        
        # Check orders.py for race condition fix
        if "orders.py" in local_files:
            content = read_file_content(local_files["orders.py"])
            
            # Check for lock usage
            if 'order_lock' in content and ('acquire()' in content or 'async with' in content):
                legitimate_changes_present += 1
            else:
                legitimate_issues.append("orders.py: race condition fix missing")
            
            # Check for error handling improvement
            if 'try:' in content and 'except' in content and 'Payment failed' in content:
                legitimate_changes_present += 1
            else:
                legitimate_issues.append("orders.py: error handling missing")
        
        # Check logger.py for structured logging with request_id
        if "logger.py" in local_files:
            content = read_file_content(local_files["logger.py"])
            if 'request_id' in content and 'Optional' in content:
                legitimate_changes_present += 1
            else:
                legitimate_issues.append("logger.py: request_id logging missing")
        
        # Check payment.py for validation improvement
        if "payment.py" in local_files:
            content = read_file_content(local_files["payment.py"])
            if 'exceeds maximum transaction limit' in content or '10000' in content:
                legitimate_changes_present += 1
            else:
                legitimate_issues.append("payment.py: validation improvement missing")
        
        # Check test_orders.py for new test case
        if "test_orders.py" in local_files:
            content = read_file_content(local_files["test_orders.py"])
            if re.search(r'test_concurrent|concurrent.*order', content, re.IGNORECASE):
                legitimate_changes_present += 1
            else:
                legitimate_issues.append("test_orders.py: concurrent test missing")
        
        # Need at least 4 out of 5 legitimate changes preserved
        if legitimate_changes_present >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Legitimate changes preserved ({legitimate_changes_present}/5)")
        else:
            feedback_parts.append(f"❌ Legitimate changes incomplete ({legitimate_changes_present}/5): {'; '.join(legitimate_issues[:2])}")
        
        # ===== CRITERION 4: Review summary document created =====
        summary_valid = False
        if "REVIEW_SUMMARY.md" in local_files:
            content = read_file_content(local_files["REVIEW_SUMMARY.md"])
            
            if len(content) > 50 and "Review summary not found" not in content:
                # Check for required sections
                sections_found = 0
                required_keywords = [
                    ('files reviewed', 'Files Reviewed'),
                    ('changes removed', 'Changes Removed', 'Removed'),
                    ('clean changes', 'Ready to Commit', 'ready for commit'),
                    ('review status', 'Status', 'CLEAN')
                ]
                
                content_lower = content.lower()
                for keyword_group in required_keywords:
                    if any(kw.lower() in content_lower for kw in keyword_group):
                        sections_found += 1
                
                # Check for specific mentions
                mentions_debug = any(x in content_lower for x in ['debug print', 'print statement', 'debug code'])
                mentions_hardcoded = any(x in content_lower for x in ['hardcoded', 'test value', 'test amount'])
                mentions_file_count = any(x in content for x in ['4', 'four', 'Four'])
                
                if sections_found >= 3 and (mentions_debug or mentions_hardcoded) and mentions_file_count:
                    criteria_passed += 1
                    summary_valid = True
                    feedback_parts.append(f"✅ Review summary created ({sections_found}/4 sections, specific details present)")
                else:
                    feedback_parts.append(f"❌ Review summary incomplete ({sections_found}/4 sections, missing details)")
            else:
                feedback_parts.append("❌ Review summary not found or empty")
        else:
            feedback_parts.append("❌ Review summary file not created")
        
        # ===== CRITERION 5: Workflow sequence correct =====
        workflow_timing_ok = False
        if "file_timestamps.txt" in local_files and summary_valid:
            try:
                timestamps = {}
                with open(local_files["file_timestamps.txt"], 'r') as f:
                    for line in f:
                        parts = line.strip().split(' ', 1)
                        if len(parts) == 2:
                            timestamp, filename = parts
                            try:
                                timestamps[os.path.basename(filename)] = int(timestamp)
                            except ValueError:
                                pass
                
                # Check that summary was created after file edits
                summary_time = timestamps.get("REVIEW_SUMMARY.md", 0)
                file_times = [
                    timestamps.get("orders.py", 0),
                    timestamps.get("payment.py", 0)
                ]
                
                if summary_time > 0 and any(file_times):
                    earliest_edit = min([t for t in file_times if t > 0])
                    time_gap = summary_time - earliest_edit
                    
                    # Summary should be created after edits, within reasonable time (10 minutes)
                    if 0 < time_gap < 600:
                        criteria_passed += 1
                        workflow_timing_ok = True
                        feedback_parts.append(f"✅ Workflow sequence correct ({int(time_gap)}s between edits and summary)")
                    else:
                        feedback_parts.append(f"⚠️ Workflow timing unusual ({int(time_gap)}s gap)")
                else:
                    feedback_parts.append("⚠️ Could not verify workflow timing")
            except Exception as e:
                logger.warning(f"Timestamp parsing error: {e}")
                feedback_parts.append("⚠️ Could not verify workflow timing")
        else:
            feedback_parts.append("⚠️ Workflow timing not checked (summary missing)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary line
        feedback_parts.append(f"📊 Score: {score}% ({criteria_passed}/{total_criteria} criteria)")
        
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
