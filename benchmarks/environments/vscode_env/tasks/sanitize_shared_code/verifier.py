#!/usr/bin/env python3
"""
Verifier for Sanitize Shared Code task
Checks that sensitive credentials have been replaced with placeholders
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sanitize_code(traj, env_info, task_info):
    """
    Verify that code has been sanitized properly
    
    Checks:
    1. All hardcoded secrets removed from files
    2. Placeholder values present
    3. SECRETS_REMOVED.md exists with meaningful content
    4. Python syntax remains valid
    
    Returns:
        dict: {"passed": bool, "score": int, "feedback": str}
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workspace = "/home/ga/workspace/flask_demo"
    
    # Files to check
    files_to_check = {
        "app.py": f"{workspace}/app.py",
        "config.py": f"{workspace}/config.py",
        "test_app.py": f"{workspace}/test_app.py"
    }
    
    # Known secrets that MUST be removed
    forbidden_secrets = [
        "MyS3cr3tP@ssw0rd2024!",  # DB password
        "sk_live_51K7xYzIqPqHMN8vwxQ0hB3mY9",  # Stripe secret
        "AKIAIOSFODNN7EXAMPLE",  # AWS access key
        "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",  # AWS secret
        "SG.xYz123AbC456DeF789.1234567890abcdefghijklmnopqrstuvwxyz",  # SendGrid
        "flask-secret-key-change-in-production-xyz789",  # Flask secret
        "super-secret-jwt-token-12345",  # JWT secret
        "pk_live_51K7xYzIqPqHMN8vwAbCdEfGh"  # Stripe public
    ]
    
    # Expected placeholder patterns (flexible)
    expected_placeholders = [
        r"YOUR_\w+_HERE",
        r"<YOUR_\w+>",
        r"\*\*\*\*+",
        r"REPLACE[_-]ME",
        r"PLACEHOLDER",
        r"your-\w+-here",
        r"<REPLACE[^>]*>",
        r"TODO:?\s*\w+"
    ]
    
    temp_dir = tempfile.mkdtemp(prefix='sanitize_verify_')
    
    try:
        issues = []
        sanitized_count = 0
        total_secrets = len(forbidden_secrets)
        placeholder_count = 0
        file_contents = {}
        
        # Check each file
        for file_name, file_path in files_to_check.items():
            local_file = os.path.join(temp_dir, file_name)
            
            try:
                copy_from_env(file_path, local_file)
            except Exception as e:
                issues.append(f"Failed to copy {file_name}: {str(e)}")
                continue
            
            if not os.path.exists(local_file):
                issues.append(f"Missing file: {file_name}")
                continue
            
            with open(local_file, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                file_contents[file_name] = content
            
            # Check for forbidden secrets
            for secret in forbidden_secrets:
                if secret in content:
                    # Secret still present - major issue
                    issues.append(f"🔴 UNSANITIZED SECRET in {file_name}: {secret[:15]}...")
                else:
                    sanitized_count += 1
            
            # Check for placeholder patterns
            has_placeholder = False
            for pattern in expected_placeholders:
                if re.search(pattern, content, re.IGNORECASE):
                    has_placeholder = True
                    break
            
            if has_placeholder:
                placeholder_count += 1
        
        # Check for documentation file
        docs_file = f"{workspace}/SECRETS_REMOVED.md"
        local_docs = os.path.join(temp_dir, "SECRETS_REMOVED.md")
        has_documentation = False
        doc_content = ""
        
        try:
            copy_from_env(docs_file, local_docs)
            
            if os.path.exists(local_docs):
                with open(local_docs, 'r', encoding='utf-8', errors='ignore') as f:
                    doc_content = f.read()
                
                # Should mention what was removed
                keywords = ['secret', 'credential', 'api', 'key', 'password', 'removed', 'sanitized', 'replaced']
                keyword_count = sum(1 for kw in keywords if kw in doc_content.lower())
                
                if keyword_count >= 2 and len(doc_content.strip()) > 50:
                    has_documentation = True
                elif len(doc_content.strip()) <= 50:
                    issues.append("❌ SECRETS_REMOVED.md is too short (< 50 chars)")
                else:
                    issues.append("❌ SECRETS_REMOVED.md doesn't mention security terms")
            else:
                issues.append("❌ SECRETS_REMOVED.md not found")
        except Exception as e:
            issues.append(f"❌ Failed to check SECRETS_REMOVED.md: {str(e)}")
        
        # Check syntax is still valid (files should be parseable Python)
        syntax_valid = True
        for file_name, content in file_contents.items():
            try:
                compile(content, file_name, 'exec')
            except SyntaxError as e:
                issues.append(f"❌ Syntax error in {file_name}: {str(e)}")
                syntax_valid = False
        
        # Scoring
        secrets_removed_pct = sanitized_count / total_secrets if total_secrets > 0 else 0
        
        # Success criteria - ALL must pass
        all_secrets_removed = len([i for i in issues if "UNSANITIZED SECRET" in i]) == 0
        has_placeholders = placeholder_count >= 2  # At least 2 files have placeholders
        
        success = (
            all_secrets_removed and
            has_placeholders and
            has_documentation and
            syntax_valid
        )
        
        # Feedback construction
        feedback_parts = []
        
        if all_secrets_removed:
            feedback_parts.append(f"✅ All {total_secrets} secrets successfully removed")
        else:
            remaining = total_secrets - sanitized_count
            feedback_parts.append(f"🔴 {remaining} secrets still present in code!")
        
        if has_placeholders:
            feedback_parts.append(f"✅ Placeholders found in {placeholder_count} files")
        else:
            feedback_parts.append(f"❌ No placeholders found (need in at least 2 files)")
        
        if has_documentation:
            feedback_parts.append("✅ SECRETS_REMOVED.md properly documented")
        else:
            feedback_parts.append("❌ SECRETS_REMOVED.md missing or inadequate")
        
        if syntax_valid:
            feedback_parts.append("✅ All files have valid Python syntax")
        else:
            feedback_parts.append("❌ Syntax errors detected")
        
        # Add specific issues
        if issues:
            feedback_parts.append(f"Issues: {'; '.join(issues)}")
        
        # Calculate score
        if success:
            score = 100
            feedback = "✅ SUCCESS: " + " | ".join(feedback_parts)
        else:
            # Partial scoring
            score = 0
            if all_secrets_removed:
                score += 50
            else:
                score += int(secrets_removed_pct * 50)
            
            if has_placeholders:
                score += 20
            if has_documentation:
                score += 15
            if syntax_valid:
                score += 15
            
            feedback = "❌ INCOMPLETE: " + " | ".join(feedback_parts)
        
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
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        if os.path.exists(temp_dir):
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)
