#!/usr/bin/env python3
"""
Verifier for Find API Usage Patterns task
Checks that user searched codebase and documented API usage patterns
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


def verify_api_learning(traj, env_info, task_info):
    """
    Verify that user found API usage examples and documented patterns.
    
    Checks:
    1. Summary file api_usage_learnings.md exists
    2. File mentions at least 3 service files where method is used
    3. File contains analytical insights (not just code)
    4. File discusses specific code patterns
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy the exported learnings file from /tmp
    learnings_path = "/tmp/api_usage_learnings.md"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.md', mode='w+')
    
    try:
        copy_from_env(learnings_path, temp_file.name)
        
        if not os.path.exists(temp_file.name):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Summary file 'api_usage_learnings.md' was not created"
            }
        
        content = read_file_content(temp_file.name)
        
        # Check if file was actually created (not just placeholder)
        if not content or content.strip() == "not_created" or len(content.strip()) < 100:
            return {
                "passed": False,
                "score": 0.1,
                "feedback": "❌ Summary file exists but appears empty or too brief (needs at least 100 characters of content)"
            }
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # List of service files that contain validate_with_schema
        service_files = [
            "user_service.py",
            "payment_service.py", 
            "order_service.py",
            "product_service.py",
            "auth_service.py",
            "notification_service.py"
        ]
        
        # Criterion 1: Check for file path references (40% weight)
        mentioned_files = []
        for service_file in service_files:
            # Check for various ways the file might be mentioned
            patterns = [
                service_file,
                f"services/{service_file}",
                f"services\\{service_file}",  # Windows path
                service_file.replace('.py', '')  # Without extension
            ]
            if any(pattern.lower() in content.lower() for pattern in patterns):
                mentioned_files.append(service_file)
        
        file_score = 0
        if len(mentioned_files) >= 3:
            criteria_passed += 1
            file_score = 1.0
            feedback_parts.append(f"✅ Found {len(mentioned_files)} usage examples: {', '.join(mentioned_files[:3])}")
        elif len(mentioned_files) >= 2:
            file_score = 0.7
            feedback_parts.append(f"⚠️ Only {len(mentioned_files)} file(s) mentioned. Need at least 3 specific usage examples.")
        elif len(mentioned_files) >= 1:
            file_score = 0.4
            feedback_parts.append(f"⚠️ Only {len(mentioned_files)} file mentioned. Need at least 3 specific usage examples.")
        else:
            feedback_parts.append("❌ No service file examples mentioned. Need at least 3 specific files.")
        
        # Criterion 2: Check for key API-related terminology (20% weight)
        required_terms = ["validate_with_schema", "schema", "result"]
        found_terms = [term for term in required_terms if term.lower() in content.lower()]
        
        term_score = 0
        if len(found_terms) >= 3:
            criteria_passed += 1
            term_score = 1.0
            feedback_parts.append("✅ Discusses key API concepts (validate_with_schema, schema, result)")
        elif len(found_terms) >= 2:
            term_score = 0.6
            feedback_parts.append("⚠️ Missing some key terminology about the API")
        else:
            feedback_parts.append("❌ Summary doesn't discuss key aspects of the API usage")
        
        # Criterion 3: Check for analytical content (20% weight)
        analysis_indicators = [
            "pattern", "common", "typically", "usually", "often",
            "always", "should", "must", "important", "note", 
            "insight", "approach", "way", "method", "use"
        ]
        
        analysis_count = sum(1 for indicator in analysis_indicators if indicator in content.lower())
        has_analysis = analysis_count >= 3
        
        analysis_score = 0
        if has_analysis:
            criteria_passed += 1
            analysis_score = 1.0
            feedback_parts.append("✅ Contains analytical insights about usage patterns")
        else:
            analysis_score = min(analysis_count / 3.0, 0.7)
            feedback_parts.append("⚠️ Could include more analytical insights about patterns (use words like 'typically', 'common', 'pattern')")
        
        # Criterion 4: Check for specific code patterns mentioned (20% weight)
        code_pattern_indicators = [
            "is_valid", "ValidationResult", "errors", "result.data",
            "fields", "required", "try", "except", "if", "return"
        ]
        
        pattern_count = sum(1 for indicator in code_pattern_indicators if indicator in content)
        has_code_patterns = pattern_count >= 3
        
        pattern_score = 0
        if has_code_patterns:
            criteria_passed += 1
            pattern_score = 1.0
            feedback_parts.append("✅ Discusses specific implementation patterns")
        else:
            pattern_score = min(pattern_count / 3.0, 0.7)
            feedback_parts.append("⚠️ Could discuss more specific code patterns (e.g., is_valid checks, error handling)")
        
        # Calculate weighted score
        # Weights: files(40%), terms(20%), analysis(20%), patterns(20%)
        score = (file_score * 0.4) + (term_score * 0.2) + (analysis_score * 0.2) + (pattern_score * 0.2)
        score_percent = int(score * 100)
        
        # Success threshold is 80%
        passed = score >= 0.8
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score_percent,
            "feedback": feedback,
            "details": {
                "files_mentioned": mentioned_files,
                "files_count": len(mentioned_files),
                "has_analysis": has_analysis,
                "has_code_patterns": has_code_patterns,
                "content_length": len(content),
                "criteria_passed": criteria_passed,
                "total_criteria": total_criteria
            }
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
