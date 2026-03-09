#!/usr/bin/env python3
"""
Verifier for Diagnose Cross-Platform Bug task
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


def verify_diagnostic_report(traj, env_info, task_info):
    """
    Verify that the diagnostic report correctly identifies cross-platform issues.
    
    Expected issues to find:
    1. Case mismatch in views.py: "from Models import" should be "from models import"
    2. Case mismatch in index.html: "/static/CSS/main.css" should be "/static/css/main.css"
    3. Hardcoded path in settings.py: "/Users/sam/..." should use os.path.join
    
    Args:
        traj: Trajectory (not used)
        env_info: Environment info dict containing copy_from_env function
        task_info: Task info dict (not used)
        
    Returns:
        dict: {
            "passed": bool,
            "score": int (0-100),
            "feedback": str,
            "metadata": dict (optional)
        }
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    report_path = "/home/ga/workspace/webapp/DIAGNOSTIC_REPORT.md"
    
    # Create temp file for the report
    temp_file = tempfile.NamedTemporaryFile(mode='w+', suffix='.md', delete=False)
    temp_path = temp_file.name
    temp_file.close()
    
    try:
        # Copy diagnostic report from container
        try:
            copy_from_env(report_path, temp_path)
        except Exception as e:
            logger.error(f"Failed to copy report: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Diagnostic report not found at {report_path}. Create the report file with your findings."
            }
        
        # Check if file exists and has content
        if not os.path.exists(temp_path) or os.path.getsize(temp_path) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Diagnostic report is empty or not found at {report_path}"
            }
        
        # Read report content
        try:
            with open(temp_path, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read report: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not read diagnostic report: {str(e)}"
            }
        
        # Check minimum length (should be substantial)
        if len(report_content.strip()) < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Diagnostic report is too short ({len(report_content)} characters). Provide detailed analysis of the issues."
            }
        
        # Convert to lowercase for case-insensitive matching
        report_lower = report_content.lower()
        
        # Initialize scoring
        criteria_passed = 0
        total_criteria = 3
        feedback_parts = []
        
        # Criterion 1: Identified case issue in views.py (Models vs models)
        found_views_issue = False
        views_indicators = [
            'views.py' in report_lower,
            any(keyword in report_lower for keyword in ['models', 'import', 'from models']),
            any(keyword in report_lower for keyword in ['case', 'uppercase', 'lowercase', 'models'])
        ]
        
        # More specific check
        if 'views.py' in report_lower:
            # Look for mentions of the actual bug
            if ('models' in report_lower and 'import' in report_lower) or 'from models' in report_lower:
                # Check if they mention the case issue
                views_context = report_lower
                if any(word in views_context for word in ['case', 'uppercase', 'lowercase', 'capital', 'models']):
                    found_views_issue = True
        
        if found_views_issue:
            criteria_passed += 1
            feedback_parts.append("✅ Identified case mismatch in views.py (Models vs models)")
        else:
            feedback_parts.append("❌ Missed case mismatch in views.py: 'from Models import User' should be 'from models import User'")
        
        # Criterion 2: Identified case issue in index.html (CSS vs css)
        found_html_issue = False
        html_indicators = [
            'index.html' in report_lower or 'template' in report_lower,
            any(keyword in report_lower for keyword in ['css', 'static', '/static/']),
            any(keyword in report_lower for keyword in ['case', 'uppercase', 'lowercase'])
        ]
        
        if ('index.html' in report_lower or 'template' in report_lower):
            # Look for mentions of CSS/css or static path
            if 'css' in report_lower or 'static' in report_lower:
                # Check if they mention the case issue
                if any(word in report_lower for word in ['case', 'uppercase', 'lowercase', 'capital']):
                    found_html_issue = True
                # Also accept if they specifically mention the path
                elif '/static/css' in report_lower or 'static/css' in report_lower:
                    found_html_issue = True
        
        if found_html_issue:
            criteria_passed += 1
            feedback_parts.append("✅ Identified case mismatch in index.html (/static/CSS/ vs /static/css/)")
        else:
            feedback_parts.append("❌ Missed case mismatch in templates/index.html: '/static/CSS/main.css' should be '/static/css/main.css'")
        
        # Criterion 3: Identified hardcoded path in settings.py
        found_hardcoded_path = False
        path_indicators = [
            'settings.py' in report_lower,
            any(keyword in report_lower for keyword in ['/users/', 'sam', 'absolute', 'hardcoded', 'path']),
            any(keyword in report_lower for keyword in ['secret', 'secret_key'])
        ]
        
        if 'settings.py' in report_lower:
            # Look for mentions of hardcoded path or /Users/sam
            if '/users/' in report_lower or 'sam' in report_lower:
                found_hardcoded_path = True
            # Or mentions of absolute path problem
            elif ('absolute' in report_lower or 'hardcoded' in report_lower) and 'path' in report_lower:
                found_hardcoded_path = True
            # Or mentions SECRET_KEY_FILE
            elif 'secret_key_file' in report_lower or 'secret' in report_lower:
                if 'path' in report_lower or 'absolute' in report_lower or '/users/' in report_lower:
                    found_hardcoded_path = True
        
        if found_hardcoded_path:
            criteria_passed += 1
            feedback_parts.append("✅ Identified hardcoded path in settings.py (/Users/sam/...)")
        else:
            feedback_parts.append("❌ Missed hardcoded path in settings.py: SECRET_KEY_FILE = '/Users/sam/workspace/webapp/secrets/...'")
        
        # Bonus: Mentions cross-platform concepts (not required, but good)
        mentions_cross_platform = any(keyword in report_lower for keyword in [
            'case-sensitive', 'case sensitive', 'macos', 'mac os', 'linux', 'ubuntu',
            'cross-platform', 'cross platform', 'filesystem', 'file system', 'works on my machine'
        ])
        
        if mentions_cross_platform:
            feedback_parts.append("💡 Good: Explains cross-platform concepts")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = (criteria_passed == total_criteria)  # Need all 3 issues identified
        
        # Generate feedback message
        if passed:
            feedback = f"✅ Excellent! All {total_criteria} critical issues identified. " + " | ".join(feedback_parts)
        else:
            feedback = f"⚠️ Diagnostic incomplete: Found {criteria_passed}/{total_criteria} critical issues. " + " | ".join(feedback_parts)
        
        # Metadata for debugging
        metadata = {
            'found_views_issue': found_views_issue,
            'found_html_issue': found_html_issue,
            'found_hardcoded_path': found_hardcoded_path,
            'mentions_cross_platform': mentions_cross_platform,
            'report_length': len(report_content),
            'criteria_passed': criteria_passed
        }
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "metadata": metadata
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        # Clean up temp file
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except:
                pass
