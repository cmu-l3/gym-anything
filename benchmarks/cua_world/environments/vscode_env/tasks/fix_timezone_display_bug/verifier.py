#!/usr/bin/env python3
"""
Verifier for Fix Timezone Display Bug task

Checks that the timezone handling bug has been properly fixed by:
1. Verifying formatAppointmentTime() is implemented in dateHelpers.js
2. Checking implementation uses proper timezone conversion patterns
3. Verifying AppointmentCard.js imports and uses the utility
4. Confirming buggy code patterns have been removed
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_timezone_fix(traj, env_info, task_info):
    """
    Verify that the timezone handling bug has been properly fixed.
    
    Scoring breakdown (100 points total):
    - dateHelpers.js implementation: 30 points
    - AppointmentCard.js import: 20 points
    - AppointmentCard.js usage: 20 points
    - Buggy code removal: 30 points
    
    Pass threshold: 80/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    workspace_base = "/home/ga/workspace/appointment-booking"
    date_helpers_path = f"{workspace_base}/src/utils/dateHelpers.js"
    appointment_card_path = f"{workspace_base}/src/components/AppointmentCard.js"
    
    score = 0
    feedback_parts = []
    
    # Temporary files for verification
    helpers_temp = tempfile.NamedTemporaryFile(delete=False, suffix='_helpers.js', mode='w+')
    card_temp = tempfile.NamedTemporaryFile(delete=False, suffix='_card.js', mode='w+')
    
    try:
        # === Step 1: Verify dateHelpers.js implementation (30 points) ===
        try:
            copy_from_env(date_helpers_path, helpers_temp.name)
        except Exception as e:
            feedback_parts.append(f"❌ Failed to read dateHelpers.js: {str(e)}")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(helpers_temp.name) or os.path.getsize(helpers_temp.name) == 0:
            feedback_parts.append("❌ dateHelpers.js not found or empty")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        helpers_content = read_file_content(helpers_temp.name)
        
        # Check function exists
        if "formatAppointmentTime" not in helpers_content:
            feedback_parts.append("❌ formatAppointmentTime function not found in dateHelpers.js")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check not still TODO
        if re.search(r'return\s+["\']TODO["\']', helpers_content):
            feedback_parts.append("❌ formatAppointmentTime still returns 'TODO' - not implemented")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Check for proper timezone handling patterns
        implementation_checks = {
            'has_date_constructor': bool(re.search(r'new\s+Date\s*\(', helpers_content)),
            'has_locale_method': bool(re.search(
                r'toLocaleString|toLocaleDateString|toLocaleTimeString',
                helpers_content
            )),
            'handles_utc_param': bool(re.search(r'utcTimestamp|timestamp|dateString', helpers_content))
        }
        
        implementation_score = 0
        if implementation_checks['has_date_constructor']:
            implementation_score += 10
            feedback_parts.append("✓ Uses Date constructor")
        else:
            feedback_parts.append("⚠ Missing Date constructor usage")
        
        if implementation_checks['has_locale_method']:
            implementation_score += 15
            feedback_parts.append("✓ Uses locale-aware formatting (toLocaleString/toLocaleDateString/toLocaleTimeString)")
        else:
            feedback_parts.append("⚠ Missing locale-aware formatting methods")
        
        if implementation_checks['handles_utc_param']:
            implementation_score += 5
            feedback_parts.append("✓ Function accepts timestamp parameter")
        
        if implementation_score >= 20:
            score += 30
            feedback_parts.append("✅ formatAppointmentTime properly implemented (30/30)")
        elif implementation_score >= 10:
            score += 15
            feedback_parts.append(f"⚠ formatAppointmentTime partially implemented (15/30)")
        else:
            feedback_parts.append("❌ formatAppointmentTime implementation inadequate (0/30)")
        
        # === Step 2: Verify AppointmentCard.js refactoring (40 points) ===
        try:
            copy_from_env(appointment_card_path, card_temp.name)
        except Exception as e:
            feedback_parts.append(f"❌ Failed to read AppointmentCard.js: {str(e)}")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        if not os.path.exists(card_temp.name) or os.path.getsize(card_temp.name) == 0:
            feedback_parts.append("❌ AppointmentCard.js not found or empty")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }
        
        card_content = read_file_content(card_temp.name)
        
        # Check for import statement (20 points)
        import_patterns = [
            r'import\s+.*formatAppointmentTime.*from\s+["\'].*dateHelpers',
            r'import\s+{[^}]*formatAppointmentTime[^}]*}\s+from\s+["\'].*dateHelpers',
            r'import\s+{.*}\s+from\s+["\'].*dateHelpers.*formatAppointmentTime'
        ]
        
        has_import = any(re.search(pattern, card_content) for pattern in import_patterns)
        
        if has_import:
            score += 20
            feedback_parts.append("✅ Imports formatAppointmentTime from dateHelpers (20/20)")
        else:
            feedback_parts.append("❌ Missing import of formatAppointmentTime (0/20)")
        
        # Check for function usage (20 points)
        usage_patterns = [
            r'formatAppointmentTime\s*\([^)]*scheduledTime[^)]*\)',
            r'formatAppointmentTime\s*\([^)]*appointment\s*\.\s*scheduledTime[^)]*\)'
        ]
        
        has_usage = any(re.search(pattern, card_content) for pattern in usage_patterns)
        
        if has_usage:
            score += 20
            feedback_parts.append("✅ Calls formatAppointmentTime with scheduledTime (20/20)")
        else:
            # Check if formatAppointmentTime is called at all
            if 'formatAppointmentTime(' in card_content:
                score += 10
                feedback_parts.append("⚠ Calls formatAppointmentTime but parameter unclear (10/20)")
            else:
                feedback_parts.append("❌ Doesn't call formatAppointmentTime function (0/20)")
        
        # === Step 3: Verify buggy code removal (30 points) ===
        buggy_patterns = {
            'replace_z': re.search(r'\.replace\s*\(\s*["\']Z["\']', card_content),
            'direct_toTimeString': re.search(r'\.toTimeString\s*\(\s*\)', card_content),
            'direct_toDateString': re.search(r'\.toDateString\s*\(\s*\)', card_content)
        }
        
        bugs_found = sum(1 for bug in buggy_patterns.values() if bug)
        
        if bugs_found == 0:
            score += 30
            feedback_parts.append("✅ All buggy timezone code removed (30/30)")
        elif bugs_found == 1:
            score += 15
            feedback_parts.append("⚠ Some buggy code patterns still present (15/30)")
        else:
            feedback_parts.append(f"❌ Multiple buggy patterns remain: {bugs_found} found (0/30)")
        
        # === Final Assessment ===
        passed = score >= 80
        
        if passed:
            feedback_parts.insert(0, f"✅ Task completed successfully! Score: {score}/100")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete. Score: {score}/100 (need 80+ to pass)")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": score,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temporary files
        for temp_file in [helpers_temp.name, card_temp.name]:
            if os.path.exists(temp_file):
                try:
                    os.unlink(temp_file)
                except:
                    pass
