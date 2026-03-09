#!/usr/bin/env python3
"""
Verifier for Diagnose CI/Local Mismatch task
"""

import sys
import os
import re
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_diagnosis(traj, env_info, task_info):
    """
    Verify that the agent correctly diagnosed the CI/local environment mismatch.
    
    Checks:
    1. Diagnosis file exists and has content
    2. Mentions timezone/TZ as the issue
    3. Identifies that CI uses TZ=UTC
    4. Identifies datetime.fromtimestamp behavior
    5. Provides recommended fix
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # The diagnosis file should be at this location
    container_path = "/home/ga/workspace/timestamp_service/CI_MISMATCH_DIAGNOSIS.md"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.md', mode='w+')
    
    try:
        # Copy the diagnosis file
        try:
            copy_from_env(container_path, temp_file.name)
        except Exception as e:
            logger.warning(f"Failed to copy diagnosis file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Diagnosis file not found at CI_MISMATCH_DIAGNOSIS.md"
            }
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Diagnosis file not found or empty at CI_MISMATCH_DIAGNOSIS.md"
            }
        
        # Read the content
        content = read_file_content(temp_file.name)
        
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Diagnosis file is empty"
            }
        
        # Scoring criteria
        score = 0.0
        max_score = 1.0
        feedback_parts = []
        
        # Criterion 1: File has substantive content (>200 chars) - 20%
        if len(content) >= 200:
            score += 0.20
            feedback_parts.append(f"✅ File has substantive content ({len(content)} chars)")
        else:
            feedback_parts.append(f"❌ File too short ({len(content)} chars, need ≥200)")
            # If file is too short, it's likely not a real analysis
            return {
                "passed": False,
                "score": int(score * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Mentions timezone/TZ as relevant factor - 30%
        timezone_mentioned = False
        if re.search(r'\b(timezone|TZ)\b', content, re.IGNORECASE):
            score += 0.30
            feedback_parts.append("✅ Identifies timezone/TZ as key factor")
            timezone_mentioned = True
        else:
            feedback_parts.append("❌ Does not mention timezone/TZ")
        
        # Criterion 3: Identifies CI uses TZ=UTC - 20%
        ci_utc_mentioned = False
        if re.search(r'(TZ.*UTC|UTC.*TZ|CI.*UTC.*timezone|CI.*TZ.*UTC)', content, re.IGNORECASE):
            score += 0.20
            feedback_parts.append("✅ Notes CI environment uses TZ=UTC")
            ci_utc_mentioned = True
        elif re.search(r'(CI.*environment|workflow.*UTC)', content, re.IGNORECASE):
            # Partial credit if CI environment is mentioned with UTC context
            score += 0.10
            feedback_parts.append("⚠️ Mentions CI/UTC but not explicit about TZ variable")
        else:
            feedback_parts.append("❌ Doesn't identify CI uses TZ=UTC")
        
        # Criterion 4: Identifies datetime.fromtimestamp or local time behavior - 15%
        code_issue_mentioned = False
        if re.search(r'(fromtimestamp|datetime\.fromtimestamp|local.*time.*zone)', content, re.IGNORECASE):
            score += 0.15
            feedback_parts.append("✅ Identifies fromtimestamp() behavior as root cause")
            code_issue_mentioned = True
        else:
            feedback_parts.append("⚠️ Doesn't pinpoint the specific code issue")
        
        # Criterion 5: Provides a recommended fix or workaround - 15%
        fix_provided = False
        fix_keywords = ['fix', 'solution', 'resolve', 'workaround', 'recommended', 'change', 'should', 'modify']
        if any(keyword in content.lower() for keyword in fix_keywords):
            # Check if there's actual actionable content, not just the word
            fix_mentions = sum(1 for keyword in fix_keywords if keyword in content.lower())
            if fix_mentions >= 2 or len(content) > 300:
                score += 0.15
                feedback_parts.append("✅ Provides recommended fix/workaround")
                fix_provided = True
            else:
                score += 0.07
                feedback_parts.append("⚠️ Mentions fix but lacks detail")
        else:
            feedback_parts.append("⚠️ Missing recommended fix/solution")
        
        # Calculate final score (out of 100)
        final_score = int(score * 100)
        
        # Determine success (need at least 70% = 0.70)
        passed = score >= 0.70
        
        if passed:
            feedback_parts.insert(0, "🎉 Successfully diagnosed CI/local mismatch!")
        else:
            feedback_parts.insert(0, "❌ Incomplete or incorrect diagnosis")
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n📊 Score: {final_score}/100"
        
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
            "feedback": f"❌ Verification failed: {str(e)}"
        }
    
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
