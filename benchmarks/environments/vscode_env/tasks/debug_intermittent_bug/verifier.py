#!/usr/bin/env python3
"""
Verifier for Debug Intermittent Bug task
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


def verify_debugging_task(traj, env_info, task_info):
    """
    Verify that the debugging task was completed correctly.
    
    Checks:
    1. Instrumentation added to database.js (console.log with timing info)
    2. DEBUGGING_NOTES.md exists with sufficient content
    3. Documentation mentions relevant debugging concepts
    4. Documentation includes evidence/log snippets
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='debug_verify_')
    
    try:
        # Copy the modified files
        database_path = "/home/ga/workspace/api_service/lib/database.js"
        notes_path = "/home/ga/workspace/api_service/DEBUGGING_NOTES.md"
        
        # Also try /tmp paths (export_result.sh copies there)
        database_tmp = "/tmp/database.js"
        notes_tmp = "/tmp/DEBUGGING_NOTES.md"
        
        local_database = os.path.join(temp_dir, "database.js")
        local_notes = os.path.join(temp_dir, "DEBUGGING_NOTES.md")
        
        # Try to copy database.js
        database_copied = False
        try:
            copy_from_env(database_path, local_database)
            database_copied = True
        except:
            try:
                copy_from_env(database_tmp, local_database)
                database_copied = True
            except:
                pass
        
        # Try to copy DEBUGGING_NOTES.md
        notes_copied = False
        try:
            copy_from_env(notes_path, local_notes)
            notes_copied = True
        except:
            try:
                copy_from_env(notes_tmp, local_notes)
                notes_copied = True
            except:
                pass
        
        criteria_passed = 0
        max_criteria = 4
        feedback_parts = []
        
        # Criterion 1: Check instrumentation in database.js
        instrumentation_ok = False
        if database_copied and os.path.exists(local_database):
            db_content = read_file_content(local_database)
            
            # Count console.log statements
            log_count = db_content.count("console.log") + db_content.count("console.debug") + db_content.count("console.info")
            
            # Check for timing/timestamp related code
            has_timing = any(keyword in db_content for keyword in [
                "Date.now()", "timestamp", "new Date()", "performance.now()", "Date()"
            ])
            
            # Check for connection pool state logging
            has_pool_logging = any(keyword in db_content for keyword in [
                "activeConnections", "queue.length", "maxConnections", "this.queue", "this.activeConnections"
            ])
            
            if log_count >= 3:
                criteria_passed += 1
                feedback_parts.append(f"✅ Instrumentation added ({log_count} log statements)")
                instrumentation_ok = True
                
                if has_timing:
                    feedback_parts.append("✅ Timestamp/timing information included")
                if has_pool_logging:
                    feedback_parts.append("✅ Connection pool state logging detected")
            else:
                feedback_parts.append(f"❌ Insufficient instrumentation ({log_count} log statements, need at least 3)")
        else:
            feedback_parts.append("❌ Could not read database.js file")
        
        # Criterion 2: Check DEBUGGING_NOTES.md exists and has content
        notes_exists = False
        notes_content = ""
        if notes_copied and os.path.exists(local_notes):
            notes_exists = True
            notes_content = read_file_content(local_notes)
            notes_length = len(notes_content.strip())
            
            if notes_length >= 200:
                criteria_passed += 1
                feedback_parts.append(f"✅ Documentation file created ({notes_length} characters)")
            else:
                feedback_parts.append(f"❌ Documentation too short ({notes_length} characters, need at least 200)")
        else:
            feedback_parts.append("❌ DEBUGGING_NOTES.md file not found")
        
        # Criterion 3: Check documentation mentions relevant concepts
        if notes_exists and notes_content:
            relevant_keywords = [
                "race condition", "race-condition", "race",
                "connection pool", "pool", "connections",
                "timeout", "concurrent", "concurrency",
                "async", "asynchronous", "timing",
                "queue", "parallel", "simultaneously"
            ]
            
            notes_lower = notes_content.lower()
            found_keywords = [kw for kw in relevant_keywords if kw in notes_lower]
            
            if len(found_keywords) >= 2:
                criteria_passed += 1
                feedback_parts.append(f"✅ Documentation mentions relevant concepts: {', '.join(found_keywords[:3])}")
            else:
                feedback_parts.append("❌ Documentation missing key debugging concepts (race condition, connection pool, timeout, etc.)")
        
        # Criterion 4: Check documentation includes evidence/log snippets
        if notes_exists and notes_content:
            has_evidence = any(indicator in notes_content for indicator in [
                "console.log", "=>", "timestamp", "ms", "connection", 
                "[", "]", "LOG:", "DEBUG:", "INFO:",
                "activeConnections", "queue"
            ])
            
            has_code_formatting = (
                "```" in notes_content or
                notes_content.count("    ") >= 2 or
                notes_content.count("console.") >= 2
            )

            if has_evidence and has_code_formatting:
                criteria_passed += 1
                feedback_parts.append("✅ Documentation includes concrete evidence/log snippets")
            elif has_evidence:
                feedback_parts.append("⚠️ Evidence mentioned, but formatting is weak")
            else:
                feedback_parts.append("❌ Documentation does not include concrete evidence")

        score = int((criteria_passed / max_criteria) * 100)
        passed = criteria_passed >= 3 and instrumentation_ok and notes_exists
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
        }
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
