#!/usr/bin/env python3
"""
Verifier for Scope Feature Request task
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


def verify_scope_document(traj, env_info, task_info):
    """
    Verify that feature scoping document was created correctly.
    
    Checks:
    1. Document exists at correct path
    2. Minimum length (substantial analysis)
    3. Required sections present (9+ out of 11)
    4. Specific files identified (3+)
    5. Function names mentioned (2+)
    6. Data model fields discussed (3+)
    7. Validation types discussed (5+)
    8. Dependencies/libraries mentioned (2+)
    9. Risks/edge cases identified (4+)
    10. Effort estimate provided
    11. No code changes made
    
    Pass threshold: 70% (7.7/11 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='scope_verify_')
    
    try:
        # Copy the scope document
        scope_doc_path = "/tmp/SCOPE_CSV_VALIDATION.md"
        local_scope_doc = os.path.join(temp_dir, "SCOPE_CSV_VALIDATION.md")
        
        try:
            copy_from_env(scope_doc_path, local_scope_doc)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to copy scope document: {str(e)}"
            }
        
        # Check 1: Document exists and has content
        if not os.path.exists(local_scope_doc):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Scope document not found at expected location"
            }
        
        content = read_file_content(local_scope_doc)
        
        # Check 2: Minimum length (should be substantial)
        if len(content) < 500:
            return {
                "passed": False,
                "score": 9,  # 9% for at least creating file
                "feedback": f"❌ Scope document is too brief ({len(content)} chars). Need thorough analysis (minimum 500 characters)."
            }
        
        feedback = []
        score = 0.0
        max_score = 11.0
        
        # Convert content to lowercase for case-insensitive matching
        content_lower = content.lower()
        
        # Check 3: Required sections present
        required_sections = [
            "feature summary",
            "current implementation",
            "affected components",
            "data model",
            "validation rules",
            "dependencies",
            "integration points",
            "edge cases",
            "testing",
            "effort estimate",
            "implementation phases"
        ]
        
        sections_found = 0
        for section in required_sections:
            if section in content_lower:
                sections_found += 1
        
        if sections_found >= 9:
            score += 2.0
            feedback.append(f"✅ Document structure complete ({sections_found}/11 sections)")
        elif sections_found >= 7:
            score += 1.5
            feedback.append(f"⚠️  Most sections present ({sections_found}/11)")
        elif sections_found >= 5:
            score += 1.0
            feedback.append(f"⚠️  Some sections present ({sections_found}/11)")
        else:
            feedback.append(f"❌ Missing many key sections ({sections_found}/11)")
        
        # Check 4: Specific files identified
        key_files = [
            "csv_parser.py",
            "upload.py",
            "models.py",
            "storage.py"
        ]
        
        files_mentioned = sum(1 for f in key_files if f in content)
        
        if files_mentioned >= 3:
            score += 2.0
            feedback.append(f"✅ Key files identified ({files_mentioned}/{len(key_files)})")
        elif files_mentioned >= 2:
            score += 1.0
            feedback.append(f"⚠️  Some key files identified ({files_mentioned}/{len(key_files)})")
        else:
            feedback.append(f"❌ Key files not properly identified ({files_mentioned}/{len(key_files)})")
        
        # Check 5: Function names mentioned
        key_functions = ["parse_csv", "upload_csv", "save_dataset"]
        functions_mentioned = sum(1 for f in key_functions if f in content)
        
        if functions_mentioned >= 2:
            score += 1.0
            feedback.append(f"✅ Key functions identified ({functions_mentioned}/3)")
        elif functions_mentioned >= 1:
            score += 0.5
            feedback.append(f"⚠️  Some functions identified ({functions_mentioned}/3)")
        else:
            feedback.append(f"❌ Key functions not mentioned")
        
        # Check 6: Data model fields discussed
        model_fields = ["timestamp", "user_email", "value", "category"]
        fields_mentioned = sum(1 for f in model_fields if f in content_lower)
        
        if fields_mentioned >= 3:
            score += 1.5
            feedback.append(f"✅ Data model fields analyzed ({fields_mentioned}/4)")
        elif fields_mentioned >= 2:
            score += 0.75
            feedback.append(f"⚠️  Some data fields mentioned ({fields_mentioned}/4)")
        else:
            feedback.append(f"❌ Data model not properly analyzed")
        
        # Check 7: Validation types discussed
        validation_keywords = [
            "email",
            "date",
            "timestamp",
            "format",
            "required",
            "validation",
            "check",
            "verify"
        ]
        
        validations_mentioned = sum(1 for kw in validation_keywords if kw in content_lower)
        
        if validations_mentioned >= 5:
            score += 1.0
            feedback.append(f"✅ Comprehensive validation requirements ({validations_mentioned} keywords)")
        elif validations_mentioned >= 3:
            score += 0.5
            feedback.append(f"⚠️  Basic validation requirements outlined ({validations_mentioned} keywords)")
        else:
            feedback.append(f"❌ Insufficient validation analysis")
        
        # Check 8: Dependencies/libraries mentioned
        library_keywords = [
            "requirements.txt",
            "cerberus",
            "marshmallow",
            "pydantic",
            "validator",
            "library",
            "dependency",
            "package"
        ]
        
        libs_mentioned = sum(1 for lib in library_keywords if lib in content_lower)
        
        if libs_mentioned >= 2:
            score += 1.0
            feedback.append(f"✅ Dependencies/libraries considered ({libs_mentioned} mentions)")
        elif libs_mentioned >= 1:
            score += 0.5
            feedback.append(f"⚠️  Dependencies mentioned briefly ({libs_mentioned} mentions)")
        else:
            feedback.append(f"❌ Dependencies section missing or incomplete")
        
        # Check 9: Risks/edge cases identified
        risk_indicators = [
            "risk",
            "edge case",
            "challenge",
            "issue",
            "problem",
            "backward compatible",
            "performance",
            "large file",
            "malformed",
            "error handling"
        ]
        
        risks_count = sum(1 for risk in risk_indicators if risk in content_lower)
        
        if risks_count >= 4:
            score += 1.5
            feedback.append(f"✅ Thorough risk analysis ({risks_count} risk indicators)")
        elif risks_count >= 2:
            score += 0.75
            feedback.append(f"⚠️  Some risks identified ({risks_count} risk indicators)")
        else:
            feedback.append(f"❌ Insufficient risk analysis")
        
        # Check 10: Effort estimate provided
        estimate_keywords = [
            "hour",
            "day",
            "week",
            "estimate",
            "complexity",
            "time",
            "effort"
        ]
        
        has_estimate = any(kw in content_lower for kw in estimate_keywords)
        
        if has_estimate:
            score += 1.0
            feedback.append("✅ Effort estimate provided")
        else:
            feedback.append("❌ Missing effort estimate")
        
        # Check 11: Verify no code changes made
        # Copy git status file
        git_status_path = "/tmp/git_status_scope.txt"
        local_git_status = os.path.join(temp_dir, "git_status.txt")
        
        code_files_modified = False
        try:
            copy_from_env(git_status_path, local_git_status)
            
            if os.path.exists(local_git_status):
                with open(local_git_status, 'r') as f:
                    status_content = f.read().strip()
                
                # Check if any .py files or requirements.txt were modified
                # SCOPE_CSV_VALIDATION.md being new/modified is OK
                # ?? SCOPE_CSV_VALIDATION.md is acceptable
                for line in status_content.split('\n'):
                    if line and not line.strip().endswith('SCOPE_CSV_VALIDATION.md'):
                        # Some other file was modified
                        if '.py' in line or 'requirements.txt' in line:
                            code_files_modified = True
                            break
        except Exception as e:
            logger.warning(f"Could not check git status: {e}")
        
        if not code_files_modified:
            score += 1.0
            feedback.append("✅ No code files modified (analysis only)")
        else:
            feedback.append("❌ Code files were modified (should be analysis only)")
        
        # Calculate final reward
        reward = score / max_score
        score_percent = int(reward * 100)
        
        # Determine pass/fail
        passed = reward >= 0.70
        
        # Quality tier
        if reward >= 0.90:
            tier = "🌟 EXCELLENT"
        elif reward >= 0.75:
            tier = "✅ GOOD"
        elif reward >= 0.70:
            tier = "✓ PASS"
        elif reward >= 0.50:
            tier = "⚠️  NEEDS IMPROVEMENT"
        else:
            tier = "❌ INSUFFICIENT"
        
        feedback_str = f"{tier} - Feature Scoping Score: {score_percent}% ({score:.1f}/{max_score} criteria)\n" + " | ".join(feedback)
        
        return {
            "passed": passed,
            "score": score_percent,
            "feedback": feedback_str
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
