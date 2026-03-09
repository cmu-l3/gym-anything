#!/usr/bin/env python3
"""
Verifier for investigate_legacy_utility@1 task
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import check_file_exists, read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_archaeology_report(traj, env_info, task_info):
    """
    Verify that the agent conducted proper code archaeology investigation.
    
    Checks:
    1. Report file exists at /home/ga/workspace/ARCHAEOLOGY_REPORT.md
    2. Contains required sections (historical context, current state, recommendation)
    3. References original 2019 commit context
    4. Identifies multiple file locations
    5. Discusses test coverage
    6. Provides actionable recommendation
    
    Returns:
        dict with keys: passed (bool), score (float 0-100), feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ Copy function not available"}
    
    report_path = "/home/ga/workspace/ARCHAEOLOGY_REPORT.md"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.md', mode='w+')
    
    try:
        # Try to copy the report file
        try:
            copy_from_env(report_path, temp_file.name)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"❌ Failed to find report file at {report_path}: {str(e)}"
            }
        
        # Check if file exists and has content
        if not os.path.exists(temp_file.name) or os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Report file doesn't exist or is empty at {report_path}"
            }
        
        # Read report content
        try:
            with open(temp_file.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to read report: {str(e)}"
            }
        
        if not content or len(content.strip()) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Report file is empty"
            }
        
        # Start verification
        score = 0.0
        feedback_parts = []
        
        # Check 1: Minimum length (15% weight) - should be substantive
        if len(content) < 200:
            feedback_parts.append(f"⚠️ Report too short ({len(content)} chars, expected 200+)")
        else:
            score += 0.15
            feedback_parts.append(f"✅ Report has adequate length ({len(content)} chars)")
        
        # Check 2: Contains required sections (25% weight)
        required_sections = {
            "historical": ["historical", "history", "origin", "original", "when", "introduced"],
            "current": ["current", "state", "location", "where", "usage", "used"],
            "recommendation": ["recommend", "conclusion", "should", "decision", "action"]
        }
        
        content_lower = content.lower()
        sections_found = 0
        section_details = []
        
        for section_name, keywords in required_sections.items():
            if any(kw in content_lower for kw in keywords):
                sections_found += 1
                section_details.append(f"✅ '{section_name}' section")
            else:
                section_details.append(f"⚠️ Missing '{section_name}' section")
        
        section_score = (sections_found / len(required_sections)) * 0.25
        score += section_score
        feedback_parts.extend(section_details)
        
        # Check 3: References original commit context (20% weight)
        # Should mention 2019, SQL injection, vulnerability, security
        historical_keywords = ["2019", "injection", "sql", "vulnerability", "security", "attack"]
        historical_mentions = sum(1 for kw in historical_keywords if kw in content_lower)
        
        if historical_mentions >= 2:
            score += 0.20
            feedback_parts.append(f"✅ References original security context ({historical_mentions} keywords found)")
        elif historical_mentions == 1:
            score += 0.10
            feedback_parts.append("⚠️ Weak reference to original commit context")
        else:
            feedback_parts.append("❌ No reference to original 2019 security context")
        
        # Check 4: Identifies multiple code locations (20% weight)
        file_locations = ["login.py", "registration.py", "validators.py", "endpoints.py"]
        files_mentioned = sum(1 for f in file_locations if f in content)
        
        # Also check for directory mentions
        path_mentions = ["auth", "api", "utils"]
        paths_mentioned = sum(1 for p in path_mentions if p in content_lower)
        
        total_location_mentions = files_mentioned + (paths_mentioned // 2)  # Paths count as half
        
        if files_mentioned >= 3:
            score += 0.20
            feedback_parts.append(f"✅ Identified {files_mentioned} file locations")
        elif files_mentioned >= 2:
            score += 0.12
            feedback_parts.append(f"⚠️ Identified only {files_mentioned} file locations (expected 3+)")
        elif files_mentioned == 1:
            score += 0.05
            feedback_parts.append(f"⚠️ Identified only {files_mentioned} file location")
        else:
            feedback_parts.append("❌ No file locations identified")
        
        # Check 5: Discusses test coverage (10% weight)
        test_keywords = ["test", "coverage", "test_validators", "testing"]
        test_mentions = sum(1 for kw in test_keywords if kw in content_lower)
        
        if test_mentions >= 1:
            score += 0.10
            feedback_parts.append("✅ Discusses test coverage")
        else:
            feedback_parts.append("⚠️ No mention of test coverage")
        
        # Check 6: Provides actionable recommendation (10% weight)
        recommendation_keywords = [
            "remove", "keep", "refactor", "consolidate", "standardize", 
            "merge", "delete", "maintain", "update", "replace"
        ]
        
        # Check if recommendation is substantive (more than just keyword)
        recommendation_found = False
        for keyword in recommendation_keywords:
            if keyword in content_lower:
                # Check if there's context around the keyword
                idx = content_lower.find(keyword)
                if idx != -1:
                    context = content_lower[max(0, idx-20):min(len(content_lower), idx+50)]
                    if len(context) > 30:  # Has sufficient context
                        recommendation_found = True
                        break
        
        if recommendation_found:
            score += 0.10
            feedback_parts.append("✅ Provides actionable recommendation")
        else:
            feedback_parts.append("⚠️ Lacks clear actionable recommendation")
        
        # Calculate final pass/fail
        score_percentage = int(score * 100)
        passed = score >= 0.6
        
        # Build feedback message
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Final Score: {score:.2f}/1.00 ({score_percentage}%)"
        
        if passed:
            feedback += "\n✅ Code archaeology investigation complete!"
        else:
            feedback += "\n❌ Investigation incomplete - report needs more depth"
            if score < 0.3:
                feedback += "\n💡 Tip: Use git log, git blame, and VSCode search features"
        
        return {
            "passed": passed,
            "score": score_percentage,
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
        # Clean up temp file
        if os.path.exists(temp_file.name):
            try:
                os.unlink(temp_file.name)
            except:
                pass
