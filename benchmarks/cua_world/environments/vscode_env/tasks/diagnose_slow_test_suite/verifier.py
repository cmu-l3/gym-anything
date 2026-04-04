#!/usr/bin/env python3
"""
Verifier for Diagnose Slow Test Suite task

Checks if agent created a comprehensive test performance analysis report that:
1. Identifies slowest tests and files
2. Documents specific performance issues
3. Provides actionable recommendations
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_test_performance_analysis(traj, env_info, task_info):
    """
    Verify the test performance analysis task.
    
    Checks for:
    1. Report file exists (TEST_PERFORMANCE_ANALYSIS.md)
    2. Contains section about slowest tests
    3. Contains section about slowest files
    4. Identifies specific performance issues
    5. Mentions code locations (file names, line numbers, or test names)
    6. Provides recommendations
    7. Mentions time.sleep issue
    8. Mentions database issue
    9. Mentions at least 5 test names
    10. Mentions at least 3 specific issues
    
    Pass threshold: 7/10 criteria (70%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    container_report_path = "/home/ga/workspace/api-testing-project/TEST_PERFORMANCE_ANALYSIS.md"
    # Also check /tmp as backup (export_result.sh copies there)
    container_report_path_alt = "/tmp/TEST_PERFORMANCE_ANALYSIS.md"
    
    temp_dir = tempfile.mkdtemp(prefix='test_suite_verify_')
    
    try:
        local_report = os.path.join(temp_dir, "TEST_PERFORMANCE_ANALYSIS.md")
        
        # Try primary location first
        report_found = False
        try:
            copy_from_env(container_report_path, local_report)
            if os.path.exists(local_report) and os.path.getsize(local_report) > 0:
                report_found = True
                logger.info("Found report at primary location")
        except Exception as e:
            logger.warning(f"Could not copy from primary location: {e}")
        
        # Try alternate location if primary failed
        if not report_found:
            try:
                copy_from_env(container_report_path_alt, local_report)
                if os.path.exists(local_report) and os.path.getsize(local_report) > 0:
                    report_found = True
                    logger.info("Found report at alternate location (/tmp)")
            except Exception as e:
                logger.warning(f"Could not copy from alternate location: {e}")
        
        if not report_found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file TEST_PERFORMANCE_ANALYSIS.md not found in workspace or /tmp"
            }
        
        # Read report content
        try:
            with open(local_report, 'r', encoding='utf-8') as f:
                content = f.read()
            content_lower = content.lower()
        except Exception as e:
            return {
                "passed": False,
                "score": 10,
                "feedback": f"Report exists but could not be read: {e}"
            }
        
        # Check if file is too short (likely incomplete)
        if len(content) < 200:
            return {
                "passed": False,
                "score": 10,
                "feedback": f"Report too short ({len(content)} chars). Expected comprehensive analysis with sections for tests, files, issues, and recommendations."
            }
        
        criteria_passed = 0
        max_criteria = 10
        feedback_parts = []
        
        # Criterion 1: Report exists (already confirmed)
        criteria_passed += 1
        feedback_parts.append("✅ Report file exists")
        
        # Criterion 2: Has section about slowest tests
        has_slow_tests_section = any(phrase in content_lower for phrase in [
            "slowest test", "slow test", "top test", "slowest individual"
        ])
        if has_slow_tests_section:
            criteria_passed += 1
            feedback_parts.append("✅ Contains slowest tests section")
        else:
            feedback_parts.append("❌ Missing slowest tests section")
        
        # Criterion 3: Has section about slowest files
        has_slow_files_section = any(phrase in content_lower for phrase in [
            "slowest file", "slow file", "test file", "file aggregate"
        ])
        if has_slow_files_section:
            criteria_passed += 1
            feedback_parts.append("✅ Contains slowest files section")
        else:
            feedback_parts.append("❌ Missing slowest files section")
        
        # Criterion 4: Identifies specific issues
        has_issues_section = any(phrase in content_lower for phrase in [
            "issue", "problem", "performance bottleneck", "anti-pattern", "root cause"
        ])
        if has_issues_section:
            criteria_passed += 1
            feedback_parts.append("✅ Identifies specific issues")
        else:
            feedback_parts.append("❌ Missing specific issues identification")
        
        # Criterion 5: Mentions code locations (file names, test names, or line numbers)
        has_code_locations = (
            content.count("test_") >= 3 or  # At least 3 test names
            ".py" in content or  # File names
            "line" in content_lower or  # Line numbers
            "::" in content  # pytest-style test paths
        )
        if has_code_locations:
            criteria_passed += 1
            feedback_parts.append("✅ Includes code locations")
        else:
            feedback_parts.append("❌ Missing specific code locations")
        
        # Criterion 6: Provides recommendations
        has_recommendations = any(phrase in content_lower for phrase in [
            "recommend", "suggest", "should", "fix", "improve", "optimization", "replace"
        ])
        recommendation_count = sum(1 for phrase in ["recommend", "suggest", "should", "fix"] 
                                  if phrase in content_lower)
        if has_recommendations and recommendation_count >= 2:
            criteria_passed += 1
            feedback_parts.append("✅ Provides recommendations")
        else:
            feedback_parts.append("❌ Missing actionable recommendations")
        
        # Criterion 7: Mentions time.sleep issue (a key performance problem)
        mentions_sleep = any(phrase in content_lower for phrase in [
            "sleep", "time.sleep", "delay", "wait"
        ])
        if mentions_sleep:
            criteria_passed += 1
            feedback_parts.append("✅ Identified sleep-related issues")
        else:
            feedback_parts.append("❌ Did not identify sleep() performance issue")
        
        # Criterion 8: Mentions database issue
        mentions_db = any(phrase in content_lower for phrase in [
            "database", " db ", "get_db", "real db", "mock", "sqlalchemy"
        ])
        if mentions_db:
            criteria_passed += 1
            feedback_parts.append("✅ Identified database-related issues")
        else:
            feedback_parts.append("❌ Did not identify database performance issue")
        
        # Criterion 9: Mentions at least 5 test names (shows thorough investigation)
        test_name_pattern = r'test_\w+'
        test_names = set(re.findall(test_name_pattern, content))
        test_count = len(test_names)
        if test_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Identified {test_count} specific tests")
        else:
            feedback_parts.append(f"❌ Only identified {test_count} tests (need ≥5)")
        
        # Criterion 10: Mentions at least 3 specific issues (shows depth)
        issue_indicators = [
            len(re.findall(r'\bissue\b', content_lower)),
            len(re.findall(r'\bproblem\b', content_lower)),
            len(re.findall(r'\bbottleneck\b', content_lower)),
            content_lower.count("slow because"),
            content_lower.count("performance")
        ]
        issue_count = sum(issue_indicators)
        if issue_count >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Documents multiple issues ({issue_count} indicators)")
        else:
            feedback_parts.append(f"❌ Insufficient issue documentation ({issue_count} indicators, need ≥3)")
        
        # Calculate score (0-100)
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 70  # 70% threshold = 7/10 criteria
        
        # Create detailed feedback message
        summary = f"Score: {criteria_passed}/{max_criteria} criteria met. "
        if passed:
            summary += "Analysis is comprehensive and actionable."
        elif score >= 50:
            summary += "Analysis is present but lacks depth or specific details."
        else:
            summary += "Analysis is incomplete or superficial."
        
        feedback = summary + " | " + " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
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
        cleanup_verification_temp(temp_dir)
