#!/usr/bin/env python3
"""
Verifier for Security Audit task
"""

import sys
import os
import logging
import tempfile
import re
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_vulnerabilities_in_section(content, section_header):
    """
    Count the number of vulnerabilities documented in a specific section.
    Looks for common patterns like numbered findings, bullet points, or file references.
    """
    # Find the section
    section_pattern = rf'##?\s*{re.escape(section_header)}.*?(?=##|\Z)'
    section_match = re.search(section_pattern, content, re.IGNORECASE | re.DOTALL)
    
    if not section_match:
        return 0
    
    section_content = section_match.group(0)
    
    # Count findings using multiple heuristics
    count = 0
    
    # Method 1: Count numbered findings (e.g., "Finding 1.1:", "1.", "Finding #1")
    numbered_findings = re.findall(r'(?:finding\s*#?\d+\.?\d*|^\s*\d+\.\s+)', section_content, re.IGNORECASE | re.MULTILINE)
    count = max(count, len(numbered_findings))
    
    # Method 2: Count file locations (e.g., "server/auth.js:12", "Location: config/stripe.js")
    file_refs = re.findall(r'(?:location:|file:|found in:)?\s*[\w/]+\.(?:js|py|sql|jsx|tsx|ts)(?::\d+)?', section_content, re.IGNORECASE)
    count = max(count, len(file_refs))
    
    # Method 3: Count severity mentions (each finding should have severity)
    severity_mentions = re.findall(r'severity\s*:\s*(?:critical|high|medium|low)', section_content, re.IGNORECASE)
    count = max(count, len(severity_mentions))
    
    return count


def check_severity_levels(content):
    """
    Check if the document contains severity level classifications.
    """
    severity_patterns = [
        r'severity\s*:\s*(?:critical|high|medium|low)',
        r'\*\*severity\*\*\s*:\s*(?:critical|high|medium|low)',
        r'(?:critical|high|medium|low)\s+(?:severity|priority)',
    ]
    
    for pattern in severity_patterns:
        if re.search(pattern, content, re.IGNORECASE):
            return True
    
    return False


def count_total_vulnerabilities(content):
    """
    Count total number of vulnerabilities across the entire document.
    """
    total = 0
    
    # Count all file references
    file_refs = re.findall(r'[\w/]+\.(?:js|py|sql|jsx|tsx|ts)(?::\d+)?', content)
    total = max(total, len(file_refs))
    
    # Count severity mentions
    severity_mentions = re.findall(r'severity\s*:\s*(?:critical|high|medium|low)', content, re.IGNORECASE)
    total = max(total, len(severity_mentions))
    
    # Count "Finding" or "Vulnerability" mentions with numbers
    finding_mentions = re.findall(r'(?:finding|vulnerability)\s*#?\d+', content, re.IGNORECASE)
    total = max(total, len(finding_mentions))
    
    return total


def verify_security_audit(traj, env_info, task_info):
    """
    Verify that security audit was conducted properly.
    
    Checks:
    1. SECURITY_AUDIT.md exists
    2. Contains "Hardcoded Credentials" section with 2+ findings
    3. Contains "Weak Cryptography" section with 1+ finding
    4. Contains "SQL Injection" section with 2+ findings
    5. Contains "XSS" section with 1+ finding
    6. At least 8 total vulnerabilities documented
    7. SECURITY_TODO.md exists
    8. Severity levels present in findings
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='security_audit_verify_')
    
    try:
        # Copy exported files
        audit_file = os.path.join(temp_dir, "security_audit.md")
        todo_file = os.path.join(temp_dir, "security_todo.md")
        
        try:
            copy_from_env("/tmp/security_audit.md", audit_file)
            copy_from_env("/tmp/security_todo.md", todo_file)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to copy audit files: {str(e)}"
            }
        
        criteria_passed = 0
        feedback_parts = []
        
        # Criterion 1: SECURITY_AUDIT.md exists and is not placeholder
        audit_exists = False
        audit_content = ""
        
        if os.path.exists(audit_file) and os.path.getsize(audit_file) > 20:
            with open(audit_file, 'r', encoding='utf-8', errors='ignore') as f:
                audit_content = f.read()
            
            if "File not found" not in audit_content[:100]:
                audit_exists = True
                criteria_passed += 1
                feedback_parts.append(f"✅ SECURITY_AUDIT.md exists ({len(audit_content)} chars)")
            else:
                feedback_parts.append("❌ SECURITY_AUDIT.md not created")
        else:
            feedback_parts.append("❌ SECURITY_AUDIT.md missing or empty")
        
        if not audit_exists:
            return {
                "passed": False,
                "score": int((criteria_passed / 8) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Hardcoded Credentials section with 2+ findings
        cred_patterns = [
            'hardcoded credential',
            'hardcoded secret',
            'hardcoded api key',
            'api key',
            'credential'
        ]
        
        cred_section_found = False
        cred_count = 0
        
        for pattern in cred_patterns:
            count = count_vulnerabilities_in_section(audit_content, pattern)
            if count > 0:
                cred_section_found = True
                cred_count = max(cred_count, count)
        
        if cred_section_found and cred_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Hardcoded Credentials section with {cred_count} findings")
        elif cred_section_found:
            feedback_parts.append(f"⚠️ Hardcoded Credentials section found but only {cred_count} finding(s) (need 2+)")
        else:
            feedback_parts.append("❌ Hardcoded Credentials section not found")
        
        # Criterion 3: Weak Cryptography section with 1+ finding
        crypto_patterns = [
            'weak cryptography',
            'weak crypto',
            'cryptography',
            'hashing',
            'md5',
            'sha1'
        ]
        
        crypto_section_found = False
        crypto_count = 0
        
        for pattern in crypto_patterns:
            count = count_vulnerabilities_in_section(audit_content, pattern)
            if count > 0:
                crypto_section_found = True
                crypto_count = max(crypto_count, count)
        
        if crypto_section_found and crypto_count >= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ Weak Cryptography section with {crypto_count} finding(s)")
        elif crypto_section_found:
            feedback_parts.append("⚠️ Weak Cryptography section found but no findings")
        else:
            feedback_parts.append("❌ Weak Cryptography section not found")
        
        # Criterion 4: SQL Injection section with 2+ findings
        sql_patterns = [
            'sql injection',
            'sql',
            'injection',
            'database'
        ]
        
        sql_section_found = False
        sql_count = 0
        
        for pattern in sql_patterns:
            count = count_vulnerabilities_in_section(audit_content, pattern)
            if count > 0:
                sql_section_found = True
                sql_count = max(sql_count, count)
        
        if sql_section_found and sql_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ SQL Injection section with {sql_count} findings")
        elif sql_section_found:
            feedback_parts.append(f"⚠️ SQL Injection section found but only {sql_count} finding(s) (need 2+)")
        else:
            feedback_parts.append("❌ SQL Injection section not found")
        
        # Criterion 5: XSS section with 1+ finding
        xss_patterns = [
            'xss',
            'cross-site scripting',
            'cross site scripting',
            'innerHTML',
            'dangerouslySetInnerHTML'
        ]
        
        xss_section_found = False
        xss_count = 0
        
        for pattern in xss_patterns:
            count = count_vulnerabilities_in_section(audit_content, pattern)
            if count > 0:
                xss_section_found = True
                xss_count = max(xss_count, count)
        
        if xss_section_found and xss_count >= 1:
            criteria_passed += 1
            feedback_parts.append(f"✅ XSS Vulnerabilities section with {xss_count} finding(s)")
        elif xss_section_found:
            feedback_parts.append("⚠️ XSS section found but no findings")
        else:
            feedback_parts.append("❌ XSS Vulnerabilities section not found")
        
        # Criterion 6: At least 8 total vulnerabilities documented
        total_vulns = count_total_vulnerabilities(audit_content)
        
        if total_vulns >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ {total_vulns} total vulnerabilities documented")
        else:
            feedback_parts.append(f"❌ Only {total_vulns} vulnerabilities documented (need 8+)")
        
        # Criterion 7: SECURITY_TODO.md exists
        todo_exists = False
        
        if os.path.exists(todo_file) and os.path.getsize(todo_file) > 20:
            with open(todo_file, 'r', encoding='utf-8', errors='ignore') as f:
                todo_content = f.read()
            
            if "File not found" not in todo_content[:100]:
                todo_exists = True
                criteria_passed += 1
                feedback_parts.append(f"✅ SECURITY_TODO.md exists ({len(todo_content)} chars)")
            else:
                feedback_parts.append("❌ SECURITY_TODO.md not created")
        else:
            feedback_parts.append("❌ SECURITY_TODO.md missing or empty")
        
        # Criterion 8: Severity levels present
        has_severity = check_severity_levels(audit_content)
        
        if has_severity:
            criteria_passed += 1
            feedback_parts.append("✅ Severity levels documented")
        else:
            feedback_parts.append("❌ No severity levels found in findings")
        
        # Calculate score
        score = int((criteria_passed / 8) * 100)
        passed = score >= 65
        
        feedback = " | ".join(feedback_parts)
        
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
