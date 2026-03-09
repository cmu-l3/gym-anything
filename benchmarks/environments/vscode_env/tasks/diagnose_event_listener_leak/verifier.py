#!/usr/bin/env python3
"""
Verifier for Event Listener Memory Leak Diagnosis task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that event listener cleanup has been added to websocket-handler.js
    
    Checks:
    1. Has removeAllListeners/removeListener/off calls
    2. Has clearInterval for the ping mechanism
    3. Cleanup logic is in the close handler
    4. Removes message listener
    5. Removes error listener
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    file_path = "/home/ga/workspace/memory-leak-project/src/websocket-handler.js"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.js', mode='w+')
    
    try:
        # Copy the file from container
        copy_from_env(file_path, temp_file.name)
        
        # Check file exists and has content
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ websocket-handler.js not found or empty"
            }
        
        content = read_file_content(temp_file.name)
        
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not read file content"
            }
        
        # Initialize checks
        checks = {
            'has_removeAllListeners_or_removeListener': False,
            'has_clearInterval': False,
            'cleanup_in_close_handler': False,
            'removes_message_listener': False,
            'removes_error_listener': False
        }
        
        feedback_parts = []
        
        # Check 1: Has removeAllListeners, removeListener, or off calls
        if re.search(r'\.(removeAllListeners|removeListener|off)\s*\(', content):
            checks['has_removeAllListeners_or_removeListener'] = True
            feedback_parts.append("✅ Found listener removal method")
        else:
            feedback_parts.append("❌ No listener removal method found (removeAllListeners/removeListener/off)")
        
        # Check 2: Has clearInterval for the ping mechanism
        if 'clearInterval' in content:
            # Check if it's clearing pingInterval specifically
            if 'clearInterval(pingInterval)' in content or 'clearInterval( pingInterval )' in content:
                checks['has_clearInterval'] = True
                feedback_parts.append("✅ clearInterval(pingInterval) found")
            elif re.search(r'clearInterval\s*\(\s*pingInterval\s*\)', content):
                checks['has_clearInterval'] = True
                feedback_parts.append("✅ clearInterval for pingInterval found")
            else:
                feedback_parts.append("⚠️ clearInterval found but may not be for pingInterval")
        else:
            feedback_parts.append("❌ clearInterval not found")
        
        # Check 3-5: Cleanup logic is in the close handler
        # Extract the close handler section - this is the most critical check
        # Pattern: ws.on('close', function/arrow function body)
        close_handler_patterns = [
            # Arrow function: ws.on('close', () => { ... })
            r"ws\.on\s*\(\s*['\"]close['\"]\s*,\s*\([^)]*\)\s*=>\s*\{([^}]*(?:\{[^}]*\})*[^}]*)\}",
            # Regular function: ws.on('close', function() { ... })
            r"ws\.on\s*\(\s*['\"]close['\"]\s*,\s*function\s*\([^)]*\)\s*\{([^}]*(?:\{[^}]*\})*[^}]*)\}",
        ]
        
        close_handler_body = None
        for pattern in close_handler_patterns:
            match = re.search(pattern, content, re.DOTALL)
            if match:
                close_handler_body = match.group(1)
                break
        
        if close_handler_body:
            checks['cleanup_in_close_handler'] = True
            
            # Check if cleanup calls are within close handler
            # Look for removeAllListeners or removeListener or off
            if re.search(r'\.(removeAllListeners|removeListener|off)\s*\(', close_handler_body):
                feedback_parts.append("✅ Listener cleanup found in close handler")
                
                # Check for specific listener removals
                # Pattern 1: removeAllListeners() with no arguments (removes all)
                if re.search(r'\.removeAllListeners\s*\(\s*\)', close_handler_body):
                    checks['removes_message_listener'] = True
                    checks['removes_error_listener'] = True
                    feedback_parts.append("✅ removeAllListeners() removes all listeners")
                else:
                    # Pattern 2: Specific listener removal
                    if re.search(r"\.removeAllListeners\s*\(\s*['\"]message['\"]\s*\)", close_handler_body):
                        checks['removes_message_listener'] = True
                        feedback_parts.append("✅ Message listener removed")
                    elif re.search(r"\.removeListener\s*\(\s*['\"]message['\"]\s*,", close_handler_body):
                        checks['removes_message_listener'] = True
                        feedback_parts.append("✅ Message listener removed")
                    else:
                        feedback_parts.append("⚠️ Message listener removal not explicitly found")
                    
                    if re.search(r"\.removeAllListeners\s*\(\s*['\"]error['\"]\s*\)", close_handler_body):
                        checks['removes_error_listener'] = True
                        feedback_parts.append("✅ Error listener removed")
                    elif re.search(r"\.removeListener\s*\(\s*['\"]error['\"]\s*,", close_handler_body):
                        checks['removes_error_listener'] = True
                        feedback_parts.append("✅ Error listener removed")
                    else:
                        feedback_parts.append("⚠️ Error listener removal not explicitly found")
            else:
                feedback_parts.append("❌ No listener cleanup in close handler")
            
            # Check if clearInterval is in close handler
            if 'clearInterval' in close_handler_body:
                # Already counted in check 2, but good to note
                pass
        else:
            feedback_parts.append("❌ Could not locate close event handler")
        
        # Alternative lenient check: if removeAllListeners() without args exists anywhere
        # and clearInterval exists, give credit for message/error removal
        if re.search(r'\.removeAllListeners\s*\(\s*\)', content):
            checks['removes_message_listener'] = True
            checks['removes_error_listener'] = True
            if "✅ removeAllListeners() removes all listeners" not in ' '.join(feedback_parts):
                feedback_parts.append("✅ removeAllListeners() without args found (removes all)")
        
        # Calculate score
        score = 0.0
        passed_checks = sum(checks.values())
        
        if checks['has_removeAllListeners_or_removeListener']:
            score += 0.25
        if checks['has_clearInterval']:
            score += 0.25
        if checks['cleanup_in_close_handler']:
            score += 0.15
        if checks['removes_message_listener']:
            score += 0.175
        if checks['removes_error_listener']:
            score += 0.175
        
        score_percent = int(score * 100)
        success = score >= 0.85  # Need at least 85% of checks
        
        feedback = f"Checks: {passed_checks}/5 passed. " + " | ".join(feedback_parts)
        
        return {
            "passed": success,
            "score": score_percent,
            "feedback": feedback,
            "details": {"checks": checks}
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
