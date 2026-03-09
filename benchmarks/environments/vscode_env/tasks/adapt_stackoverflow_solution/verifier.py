#!/usr/bin/env python3
"""
Verifier for Adapt Stack Overflow Solution task
Checks that Stack Overflow Express code was properly adapted to Fastify with team conventions
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adaptation(traj, env_info, task_info):
    """
    Verify that the Stack Overflow rate limiter was adapted correctly.
    
    Checks:
    1. Rate limiter file exists
    2. Imports from config file
    3. No hardcoded values
    4. Uses config values
    5. No Express-specific code
    6. Uses Fastify patterns
    7. Has Stack Overflow attribution
    8. Error handler naming convention
    9. Server integration
    10. Cleanup of example file
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='adapt_stackoverflow_verify_')
    
    try:
        feedback_parts = []
        issues = []
        score = 0.0
        max_score = 10.0
        
        # Copy files from /tmp (exported by export_result.sh)
        rate_limiter_local = os.path.join(temp_dir, "rate_limiter.js")
        server_local = os.path.join(temp_dir, "server.js")
        cleanup_status_local = os.path.join(temp_dir, "example_cleanup_status.txt")
        
        try:
            copy_from_env("/tmp/rate_limiter.js", rate_limiter_local)
            copy_from_env("/tmp/server.js", server_local)
            copy_from_env("/tmp/example_cleanup_status.txt", cleanup_status_local)
        except Exception as e:
            logger.warning(f"Failed to copy some files: {e}")
        
        # Check 1: Rate limiter file exists and has content (1 point)
        if not os.path.exists(rate_limiter_local) or os.path.getsize(rate_limiter_local) < 50:
            issues.append("❌ Rate limiter implementation file not created or too short")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Rate limiter file not found or empty at src/middleware/rate_limiter.js",
                "details": {"checks_passed": 0, "issues": len(issues)}
            }
        
        score += 1.0
        feedback_parts.append("✅ Rate limiter file created")
        
        # Read rate limiter content
        limiter_content = read_file_content(rate_limiter_local)
        
        # Check 2: Imports from config (1.5 points)
        imports_config = bool(re.search(r"require\(['\"].*config/rate_limit\.config", limiter_content)) or \
                        bool(re.search(r"from\s+['\"].*config/rate_limit\.config", limiter_content)) or \
                        bool(re.search(r"require\(['\"]\.\.\/\.\.\/config\/rate_limit\.config", limiter_content))
        
        if imports_config:
            score += 1.5
            feedback_parts.append("✅ Imports configuration from config file")
        else:
            issues.append("❌ Does not import from config/rate_limit.config.js")
        
        # Check 3: No hardcoded values (1 point)
        hardcoded_patterns = [
            (r'\b100\b', '100'),
            (r'\b60000\b', '60000'),
            (r'["\']Too many requests["\']', "'Too many requests'")
        ]
        found_hardcoded = []
        for pattern, name in hardcoded_patterns:
            if re.search(pattern, limiter_content):
                found_hardcoded.append(name)
        
        if not found_hardcoded:
            score += 1.0
            feedback_parts.append("✅ No hardcoded magic numbers found")
        else:
            issues.append(f"❌ Contains hardcoded values: {', '.join(found_hardcoded)}")
        
        # Check 4: Uses config values (1 point)
        uses_config_vars = (
            bool(re.search(r'\bwindowMs\b', limiter_content)) and
            bool(re.search(r'\bmaxRequestsPerWindow\b', limiter_content))
        )
        if uses_config_vars:
            score += 1.0
            feedback_parts.append("✅ Uses config variables (windowMs, maxRequestsPerWindow)")
        else:
            issues.append("❌ Does not use config variables from config file")
        
        # Check 5: No Express-specific code (1 point)
        has_express_code = bool(re.search(r'\bexpress-rate-limit\b', limiter_content)) or \
                          bool(re.search(r'\(req\s*,\s*res\)', limiter_content))
        
        if not has_express_code:
            score += 1.0
            feedback_parts.append("✅ No Express-specific code found")
        else:
            issues.append("❌ Still contains Express patterns (express-rate-limit or (req, res))")
        
        # Check 6: Uses Fastify patterns (1 point)
        has_fastify = bool(re.search(r'\bfastify\b', limiter_content, re.IGNORECASE)) or \
                     bool(re.search(r'\brequest\b', limiter_content)) or \
                     bool(re.search(r'\breply\b', limiter_content)) or \
                     bool(re.search(r'module\.exports\s*=.*function.*\(fastify', limiter_content))
        
        if has_fastify:
            score += 1.0
            feedback_parts.append("✅ Uses Fastify patterns (request/reply or plugin)")
        else:
            issues.append("❌ Does not appear to use Fastify patterns")
        
        # Check 7: Has Stack Overflow attribution (0.5 points)
        has_attribution = bool(re.search(r'stackoverflow\.com', limiter_content, re.IGNORECASE)) or \
                         bool(re.search(r'stack\s*overflow', limiter_content, re.IGNORECASE)) or \
                         bool(re.search(r'@source.*stackoverflow', limiter_content, re.IGNORECASE)) or \
                         bool(re.search(r'adapted from.*stackoverflow', limiter_content, re.IGNORECASE))
        
        if has_attribution:
            score += 0.5
            feedback_parts.append("✅ Contains Stack Overflow attribution")
        else:
            issues.append("⚠️ Missing Stack Overflow source attribution in comments/JSDoc")
        
        # Check 8: Error handler naming convention (0.5 points)
        has_handle_prefix = bool(re.search(r'\bhandle[A-Z]\w*', limiter_content))
        if has_handle_prefix:
            score += 0.5
            feedback_parts.append("✅ Error handler follows naming convention (handle*)")
        else:
            issues.append("⚠️ Error handler should follow 'handle*' naming pattern")
        
        # Check 9: Server integration (1.5 points)
        if os.path.exists(server_local):
            server_content = read_file_content(server_local)
            
            imports_limiter = bool(re.search(r'require.*middleware/rate_limiter', server_content)) or \
                            bool(re.search(r'from.*middleware/rate_limiter', server_content))
            
            registers_limiter = bool(re.search(r'fastify\.register', server_content)) or \
                              bool(re.search(r'fastify\.addHook', server_content))
            
            if imports_limiter and registers_limiter:
                score += 1.5
                feedback_parts.append("✅ Rate limiter imported and registered in server.js")
            elif imports_limiter:
                score += 0.75
                feedback_parts.append("⚠️ Rate limiter imported but registration not clear")
                issues.append("⚠️ Rate limiter may not be properly registered as plugin/hook")
            else:
                issues.append("❌ Rate limiter not integrated into server.js")
        else:
            issues.append("❌ server.js not found for verification")
        
        # Check 10: Cleanup of example file (1 point)
        cleanup_status = ""
        if os.path.exists(cleanup_status_local):
            cleanup_status = read_file_content(cleanup_status_local).strip()
        
        if cleanup_status == "DELETED":
            score += 1.0
            feedback_parts.append("✅ Example file deleted (cleanup complete)")
        elif cleanup_status == "MOVED":
            score += 1.0
            feedback_parts.append("✅ Example file moved to docs/references")
        else:
            issues.append("⚠️ Original rate_limiter_example.js should be deleted or moved")
        
        # Determine success (need 70% to pass)
        passed = score >= 7.0
        
        # Build feedback
        feedback = " | ".join(feedback_parts)
        if issues:
            feedback += " || ISSUES: " + " | ".join(issues)
        
        feedback += f" || Score: {score:.1f}/{max_score}"
        
        score_normalized = score / max_score
        
        return {
            "passed": passed,
            "score": int(score_normalized * 100),
            "feedback": feedback,
            "details": {
                "score": score,
                "max_score": max_score,
                "percentage": score_normalized * 100,
                "checks_passed": len(feedback_parts),
                "issues_found": len(issues)
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
