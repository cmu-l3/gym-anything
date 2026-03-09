#!/usr/bin/env python3
"""
Verifier for consolidate_todo_markers@1
Checks that the agent successfully inventoried technical debt markers
"""

import os
import re
import sys
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify that technical debt markers were properly consolidated.
    
    Returns:
        dict with 'passed', 'score', 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    feedback_parts = []
    reward = 0.0
    
    # Step 1: Check if TECHNICAL_DEBT.md exists
    debt_file_path = "/home/ga/workspace/web_scraper/TECHNICAL_DEBT.md"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.md', mode='w+')
    
    try:
        try:
            copy_from_env(debt_file_path, temp_file.name)
        except Exception as e:
            logger.error(f"Failed to copy TECHNICAL_DEBT.md: {e}")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"❌ TECHNICAL_DEBT.md not found at {debt_file_path}"
            }
        
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "❌ TECHNICAL_DEBT.md is missing or empty"
            }
        
        feedback_parts.append("✅ TECHNICAL_DEBT.md file created")
        reward += 0.20
        
        # Step 2: Read and parse the content
        content = read_file_content(temp_file.name)
        if not content:
            return {
                "passed": False,
                "score": int(reward * 100),
                "feedback": "❌ Could not read TECHNICAL_DEBT.md content"
            }
        
        content_lower = content.lower()
        
        # Step 3: Check for priority categorization
        has_critical = 'critical' in content_lower or '🔴' in content
        has_high = 'high' in content_lower or '🟡' in content
        has_medium = 'medium' in content_lower or '🟢' in content
        
        priority_count = sum([has_critical, has_high, has_medium])
        
        if priority_count >= 3:
            feedback_parts.append("✅ Document includes priority categorization (CRITICAL/HIGH/MEDIUM)")
            reward += 0.15
        elif priority_count >= 2:
            feedback_parts.append("⚠️ Partial priority categorization (missing some levels)")
            reward += 0.08
        elif priority_count >= 1:
            feedback_parts.append("⚠️ Minimal priority categorization (only one level found)")
            reward += 0.03
        else:
            feedback_parts.append("❌ No priority categorization found")
        
        # Step 4: Check that markers are referenced with file locations
        file_reference_pattern = r'(?:scraper|tests)/[\w_]+\.py'
        file_references = re.findall(file_reference_pattern, content)
        unique_files = set(file_references)
        
        if len(file_references) >= 8:
            feedback_parts.append(f"✅ Found {len(file_references)} file location references")
            reward += 0.15
        elif len(file_references) >= 5:
            feedback_parts.append(f"⚠️ Found {len(file_references)} file references (expected at least 8)")
            reward += 0.10
        elif len(file_references) >= 3:
            feedback_parts.append(f"⚠️ Found only {len(file_references)} file references")
            reward += 0.05
        else:
            feedback_parts.append(f"❌ Insufficient file references ({len(file_references)} found)")
        
        # Step 5: Check for line number references
        line_number_pattern = r'(?:line\s*)?:?\s*(\d+)|(?:line|l)\s+(\d+)'
        line_numbers = re.findall(line_number_pattern, content)
        
        if len(line_numbers) >= 8:
            feedback_parts.append(f"✅ Includes line number references ({len(line_numbers)} found)")
            reward += 0.10
        elif len(line_numbers) >= 5:
            feedback_parts.append(f"⚠️ Some line number references ({len(line_numbers)} found)")
            reward += 0.06
        elif len(line_numbers) >= 2:
            feedback_parts.append(f"⚠️ Few line number references ({len(line_numbers)} found)")
            reward += 0.03
        else:
            feedback_parts.append("❌ Missing or insufficient line number references")
        
        # Step 6: Check that critical marker types are documented
        marker_types_found = {
            'TODO': 'todo' in content_lower,
            'FIXME': 'fixme' in content_lower,
            'HACK': 'hack' in content_lower,
            'XXX': 'xxx' in content_lower
        }
        
        types_found_count = sum(marker_types_found.values())
        
        if types_found_count >= 4:
            feedback_parts.append(f"✅ All marker types documented (TODO/FIXME/HACK/XXX)")
            reward += 0.10
        elif types_found_count >= 3:
            feedback_parts.append(f"✅ Most marker types documented ({types_found_count}/4)")
            reward += 0.08
        elif types_found_count >= 2:
            feedback_parts.append(f"⚠️ Some marker types documented ({types_found_count}/4)")
            reward += 0.04
        else:
            feedback_parts.append(f"❌ Limited marker type coverage ({types_found_count}/4)")
        
        # Step 7: Check for specific high-priority items that should be identified
        critical_markers_found = []
        
        # The XXX relative URL bug (should be marked as critical)
        if 'relative' in content_lower and 'url' in content_lower:
            critical_markers_found.append("relative URL issue")
        
        # The rate limiter blocking problem (should be high priority)
        if (('rate' in content_lower or 'limiter' in content_lower) and 
            ('block' in content_lower or 'async' in content_lower or 'sleep' in content_lower)):
            critical_markers_found.append("rate limiter issue")
        
        # The hardcoded user agent (should be documented)
        if 'user' in content_lower and 'agent' in content_lower:
            critical_markers_found.append("user agent configuration")
        
        # JSON error handling
        if 'json' in content_lower and ('error' in content_lower or 'malformed' in content_lower):
            critical_markers_found.append("JSON error handling")
        
        critical_count = len(critical_markers_found)
        if critical_count >= 3:
            feedback_parts.append(f"✅ Key high-impact issues identified: {', '.join(critical_markers_found)}")
            reward += 0.15
        elif critical_count >= 2:
            feedback_parts.append(f"✅ Some critical issues identified: {', '.join(critical_markers_found)}")
            reward += 0.10
        elif critical_count >= 1:
            feedback_parts.append(f"⚠️ Limited critical issue identification")
            reward += 0.05
        else:
            feedback_parts.append("❌ Key critical issues not identified")
        
        # Step 8: Check formatting quality (markdown structure)
        header_count = content.count('#')
        has_lists = content.count('-') >= 5 or content.count('*') >= 5 or content.count('1.') >= 3
        
        if header_count >= 3 and has_lists:
            feedback_parts.append("✅ Good markdown formatting with headers and lists")
            reward += 0.10
        elif header_count >= 2 or has_lists:
            feedback_parts.append("⚠️ Basic markdown formatting present")
            reward += 0.05
        else:
            feedback_parts.append("⚠️ Formatting could be improved")
            reward += 0.02
        
        # Step 9: Bonus - check if any items were marked as resolved or if summary is present
        has_summary = 'summary' in content_lower or 'total' in content_lower
        has_resolved = 'resolved' in content_lower or '✅' in content or 'fixed' in content_lower
        
        if has_summary or has_resolved:
            feedback_parts.append("🌟 BONUS: Includes summary or resolved items")
            reward += 0.05
        
        # Calculate final score (cap at 1.0)
        reward = min(reward, 1.0)
        score = int(reward * 100)
        
        # Success threshold is 70%
        success = reward >= 0.70
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Final Score: {score}/100"
        
        if success:
            feedback += "\n✅ Task completed successfully - PR-ready documentation!"
        else:
            feedback += "\n❌ Task incomplete - documentation needs improvement"
            if priority_count < 2:
                feedback += "\nℹ️ Tip: Add priority categories (CRITICAL, HIGH, MEDIUM)"
            if len(file_references) < 5:
                feedback += "\nℹ️ Tip: Include file paths for each technical debt item"
            if len(line_numbers) < 5:
                feedback += "\nℹ️ Tip: Include line numbers for easier navigation"
        
        return {
            "passed": success,
            "score": score,
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
        # Cleanup temp file
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
