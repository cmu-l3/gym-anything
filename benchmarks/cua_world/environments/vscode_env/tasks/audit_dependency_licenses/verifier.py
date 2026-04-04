#!/usr/bin/env python3
"""
Verifier for License Audit task
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


def verify_license_audit(traj, env_info, task_info):
    """
    Verify that license audit was completed correctly.
    
    Scoring criteria:
    1. Report file exists and has content (15 points)
    2. Markdown structure present (10 points)
    3. GPL dependency identified (30 points - CRITICAL)
    4. Dependency coverage (20 points)
    5. Risk categorization present (10 points)
    6. Alternatives/recommendations provided (10 points)
    7. Executive summary/overview (5 points)
    
    Pass threshold: 70%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='license_verify_')
    
    try:
        # Copy the audit report from /tmp
        report_path = "/tmp/LICENSE_AUDIT_REPORT.md"
        local_report = os.path.join(temp_dir, "LICENSE_AUDIT_REPORT.md")
        
        try:
            copy_from_env(report_path, local_report)
        except Exception as e:
            logger.error(f"Failed to copy audit report: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ LICENSE_AUDIT_REPORT.md not found in project root. You must create this file with the audit results."
            }
        
        # Check if file exists and has content
        if not os.path.exists(local_report) or os.path.getsize(local_report) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ LICENSE_AUDIT_REPORT.md is missing or empty. Create a markdown file documenting the license audit."
            }
        
        # Read report content
        report_content = read_file_content(local_report)
        
        if len(report_content.strip()) < 100:
            return {
                "passed": False,
                "score": 5,
                "feedback": "❌ Report is too short. It should include detailed findings, risk assessment, and recommendations."
            }
        
        score = 0
        feedback_parts = []
        
        # Criterion 1: Report exists with substantial content (15 points)
        score += 15
        feedback_parts.append(f"✅ Report file created ({len(report_content)} characters)")
        
        # Criterion 2: Markdown structure (10 points)
        has_headers = bool(re.search(r'^#+\s+.+', report_content, re.MULTILINE))
        has_structure = (
            ('|' in report_content) or  # Tables
            re.search(r'^\s*[-*+]\s+', report_content, re.MULTILINE) or  # Lists
            re.search(r'^\d+\.\s+', report_content, re.MULTILINE)  # Numbered lists
        )
        
        if has_headers and has_structure:
            score += 10
            feedback_parts.append("✅ Proper markdown structure (headers + tables/lists)")
        elif has_headers or has_structure:
            score += 5
            feedback_parts.append("○ Basic markdown structure present but incomplete")
        else:
            feedback_parts.append("❌ Poor markdown formatting (no headers or structure)")
        
        # Criterion 3: GPL dependency identified (30 points - CRITICAL)
        gpl_patterns = [
            r'gpl-problematic-package',
            r'GPL[-\s]?3\.0',
            r'GPL[-\s]?v?3',
            r'GNU\s+General\s+Public\s+License',
            r'copyleft'
        ]
        
        gpl_identified = any(re.search(pattern, report_content, re.IGNORECASE) for pattern in gpl_patterns)
        gpl_flagged_as_risk = any(re.search(pattern, report_content, re.IGNORECASE) for pattern in [
            r'(high|critical|severe).*risk',
            r'risk.*level.*high',
            r'incompatible.*commercial',
            r'problematic.*GPL',
            r'GPL.*problematic',
            r'❌.*gpl',
            r'⚠️.*gpl'
        ])
        
        if gpl_identified and gpl_flagged_as_risk:
            score += 30
            feedback_parts.append("✅ GPL dependency correctly identified and flagged as high risk")
        elif gpl_identified:
            score += 20
            feedback_parts.append("○ GPL dependency mentioned but risk level unclear")
        else:
            feedback_parts.append("❌ CRITICAL: GPL-3.0 dependency (gpl-problematic-package) not identified - major compliance failure!")
        
        # Criterion 4: Dependency coverage (20 points)
        # Count package mentions in various formats
        package_mentions = set()
        
        # Look for package names with versions
        package_mentions.update(re.findall(r'[a-z0-9-]+@[\d.]+', report_content, re.IGNORECASE))
        
        # Look for package names in quotes or backticks
        package_mentions.update(re.findall(r'["`\']([a-z0-9-]+)["`\']', report_content, re.IGNORECASE))
        
        # Look for common package names mentioned
        known_packages = [
            'express', 'lodash', 'axios', 'moment', 'uuid', 'dotenv', 
            'chalk', 'yargs', 'debug', 'cors', 'body-parser', 'jsonwebtoken',
            'bcrypt', 'winston', 'jest', 'eslint', 'nodemon', 
            'gpl-problematic-package', 'unlicensed-helper'
        ]
        
        for pkg in known_packages:
            if re.search(r'\b' + re.escape(pkg) + r'\b', report_content, re.IGNORECASE):
                package_mentions.add(pkg)
        
        num_packages_documented = len(package_mentions)
        
        if num_packages_documented >= 10:
            score += 20
            feedback_parts.append(f"✅ Comprehensive coverage ({num_packages_documented} dependencies documented)")
        elif num_packages_documented >= 5:
            score += 12
            feedback_parts.append(f"○ Moderate coverage ({num_packages_documented} dependencies documented)")
        elif num_packages_documented >= 3:
            score += 6
            feedback_parts.append(f"○ Limited coverage ({num_packages_documented} dependencies documented)")
        else:
            feedback_parts.append(f"❌ Insufficient coverage (only {num_packages_documented} dependencies documented)")
        
        # Criterion 5: Risk categorization (10 points)
        has_risk_levels = bool(re.search(
            r'(high|medium|low|critical|severe).*risk|risk.*level',
            report_content,
            re.IGNORECASE
        ))
        
        has_risk_categories = (
            len(re.findall(r'\bhigh\s+risk\b', report_content, re.IGNORECASE)) > 0 and
            len(re.findall(r'\b(low|medium)\s+risk\b', report_content, re.IGNORECASE)) > 0
        )
        
        if has_risk_categories:
            score += 10
            feedback_parts.append("✅ Risk levels properly categorized (high/medium/low)")
        elif has_risk_levels:
            score += 5
            feedback_parts.append("○ Risk assessment present but not fully categorized")
        else:
            feedback_parts.append("❌ No risk categorization found")
        
        # Criterion 6: Alternatives/recommendations (10 points)
        has_alternatives = bool(re.search(
            r'(alternative|replacement|substitute|replace with|instead of|migrate to|recommend|suggestion)',
            report_content,
            re.IGNORECASE
        ))
        
        has_actionable = bool(re.search(
            r'(should|must|need to|action|next step|recommendation)',
            report_content,
            re.IGNORECASE
        ))
        
        if has_alternatives and has_actionable:
            score += 10
            feedback_parts.append("✅ Alternatives and actionable recommendations provided")
        elif has_alternatives or has_actionable:
            score += 5
            feedback_parts.append("○ Some recommendations present but incomplete")
        else:
            feedback_parts.append("❌ No alternatives or recommendations for problematic licenses")
        
        # Criterion 7: Executive summary (5 points)
        has_summary = bool(re.search(
            r'(summary|overview|executive|total.*dependencies|findings)',
            report_content,
            re.IGNORECASE
        ))
        
        if has_summary:
            score += 5
            feedback_parts.append("✅ Executive summary/overview present")
        else:
            feedback_parts.append("○ No executive summary section")
        
        # Calculate final result
        passed = score >= 70
        
        # Generate comprehensive feedback
        feedback = "\n".join(feedback_parts)
        
        if passed:
            feedback += f"\n\n🎉 PASS (Score: {score}/100)"
            feedback += "\nLicense audit successfully completed with proper risk identification and recommendations."
        else:
            feedback += f"\n\n❌ FAIL (Score: {score}/100)"
            if not gpl_identified:
                feedback += "\n⚠️  CRITICAL ISSUE: GPL-3.0 dependency not identified - this is a legal compliance blocker!"
            feedback += "\nAudit is incomplete or missing critical compliance findings."
        
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
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
