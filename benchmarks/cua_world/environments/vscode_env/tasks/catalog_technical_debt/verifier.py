#!/usr/bin/env python3
"""
Verifier for Technical Debt Catalog task
"""

import sys
import os
import logging
import tempfile
import shutil
import re
from typing import Dict, List, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_debt_catalog(traj, env_info, task_info):
    """
    Verify that technical debt catalog was created correctly.
    
    Checks:
    1. TECHNICAL_DEBT.md file exists (15%)
    2. Proper markdown structure (15%)
    3. Sufficient coverage: at least 6/10 markers (20%)
    4. Accurate file/line references (15%)
    5. Context included (15%)
    6. No false positives (10%)
    7. Organized by severity (10%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Ground truth: expected debt markers in workspace
    expected_debt = [
        {"file": "src/utils/cache.py", "line": 45, "type": "FIXME", "keyword": "memory leak"},
        {"file": "src/api/routes.js", "line": 102, "type": "TODO", "keyword": "input validation"},
        {"file": "src/auth/login.py", "line": 67, "type": "XXX", "keyword": "authentication bypass"},
        {"file": "src/db/connection.py", "line": 23, "type": "HACK", "keyword": "connection pooling"},
        {"file": "tests/test_api.js", "line": 156, "type": "TODO", "keyword": "edge case testing"},
        {"file": "src/ui/dashboard.jsx", "line": 89, "type": "TODO", "keyword": "loading state"},
        {"file": "src/utils/parser.py", "line": 134, "type": "FIXME", "keyword": "regex escaping"},
        {"file": "src/api/middleware.js", "line": 78, "type": "HACK", "keyword": "CORS workaround"},
        {"file": "config/settings.py", "line": 12, "type": "XXX", "keyword": "hardcoded"},
        {"file": "src/models/user.py", "line": 201, "type": "TODO", "keyword": "database indexes"}
    ]
    
    temp_dir = tempfile.mkdtemp(prefix='debt_verify_')
    
    try:
        # Copy TECHNICAL_DEBT.md from container
        debt_doc_path = "/home/ga/workspace/debt_project/TECHNICAL_DEBT.md"
        local_debt_doc = os.path.join(temp_dir, "TECHNICAL_DEBT.md")
        
        try:
            copy_from_env(debt_doc_path, local_debt_doc)
        except Exception as e:
            logger.warning(f"Failed to copy from primary location: {e}")
            # Try backup location
            try:
                copy_from_env("/tmp/TECHNICAL_DEBT.md", local_debt_doc)
            except Exception as e2:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ TECHNICAL_DEBT.md file not found: {str(e)}"
                }
        
        criteria_scores = {
            "file_created": 0,
            "proper_structure": 0,
            "sufficient_coverage": 0,
            "accurate_references": 0,
            "context_included": 0,
            "no_false_positives": 0,
            "organized_by_severity": 0
        }
        
        feedback_parts = []
        
        # Criterion 1: File Created (15 points)
        if os.path.exists(local_debt_doc) and os.path.getsize(local_debt_doc) >= 200:
            criteria_scores["file_created"] = 15
            feedback_parts.append("✅ Documentation file created with adequate content")
            
            with open(local_debt_doc, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        else:
            if os.path.exists(local_debt_doc):
                size = os.path.getsize(local_debt_doc)
                feedback_parts.append(f"❌ Documentation file too small ({size} bytes, minimum 200)")
            else:
                feedback_parts.append("❌ Documentation file not found")
            
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts)
            }
        
        # Criterion 2: Proper Structure (15 points)
        structure_score = 0
        
        # Check for main heading
        if re.search(r'#.*[Tt]echnical\s+[Dd]ebt', content):
            structure_score += 5
            feedback_parts.append("✅ Document has proper heading")
        else:
            feedback_parts.append("❌ Missing main 'Technical Debt' heading")
        
        # Check for sections (at least 2)
        section_count = len(re.findall(r'##\s+\w+', content))
        if section_count >= 2:
            structure_score += 5
            feedback_parts.append(f"✅ Document has {section_count} sections")
        else:
            feedback_parts.append(f"❌ Only {section_count} sections found (need at least 2)")
        
        # Check for checkbox format
        if '- [ ]' in content or '- [x]' in content:
            structure_score += 5
            feedback_parts.append("✅ Uses checkbox format for tracking")
        else:
            feedback_parts.append("⚠️ Missing checkbox format")
        
        criteria_scores["proper_structure"] = structure_score
        
        # Criterion 3: Sufficient Coverage (20 points)
        found_count = 0
        found_details = []
        
        for debt in expected_debt:
            # Check if file path OR line number OR keyword appears
            file_base = os.path.basename(debt["file"])
            file_mentioned = debt["file"] in content or file_base in content
            line_mentioned = (
                f"Line: {debt['line']}" in content or 
                f"L{debt['line']}" in content or 
                f":{debt['line']}" in content or
                str(debt['line']) in content
            )
            keyword_mentioned = debt["keyword"].lower() in content.lower()
            type_mentioned = debt["type"] in content.upper()
            
            # More lenient matching: file + (line OR keyword) OR (line + keyword + type)
            if (file_mentioned and (line_mentioned or keyword_mentioned)) or \
               (line_mentioned and keyword_mentioned and type_mentioned):
                found_count += 1
                found_details.append(f"{debt['file']}:{debt['line']}")
        
        coverage_percent = (found_count / len(expected_debt)) * 100
        
        if coverage_percent >= 60:
            criteria_scores["sufficient_coverage"] = 20
            feedback_parts.append(f"✅ Found {found_count}/{len(expected_debt)} debt markers ({coverage_percent:.0f}% coverage)")
        elif coverage_percent >= 40:
            criteria_scores["sufficient_coverage"] = int(20 * coverage_percent / 60)
            feedback_parts.append(f"⚠️ Found {found_count}/{len(expected_debt)} debt markers ({coverage_percent:.0f}% coverage - needs improvement)")
        else:
            criteria_scores["sufficient_coverage"] = 0
            feedback_parts.append(f"❌ Only found {found_count}/{len(expected_debt)} debt markers ({coverage_percent:.0f}% coverage)")
        
        # Criterion 4: Accurate References (15 points)
        accurate_refs = 0
        
        for debt in expected_debt:
            file_base = os.path.basename(debt["file"])
            # Check if both file and line are mentioned in proximity (within 150 chars)
            file_pattern = re.escape(file_base)
            
            for match in re.finditer(file_pattern, content, re.IGNORECASE):
                context = content[max(0, match.start()-100):match.end()+150]
                # Look for line number in context
                if str(debt["line"]) in context:
                    accurate_refs += 1
                    break
        
        accuracy_percent = (accurate_refs / len(expected_debt)) * 100
        
        if accuracy_percent >= 50:
            criteria_scores["accurate_references"] = 15
            feedback_parts.append(f"✅ {accurate_refs}/{len(expected_debt)} references have accurate file:line pairs")
        elif accuracy_percent >= 30:
            criteria_scores["accurate_references"] = 10
            feedback_parts.append(f"⚠️ {accurate_refs}/{len(expected_debt)} references have accurate file:line pairs (moderate)")
        else:
            criteria_scores["accurate_references"] = 5
            feedback_parts.append(f"❌ Only {accurate_refs}/{len(expected_debt)} references have accurate file:line pairs")
        
        # Criterion 5: Context Included (15 points)
        # Check that entries have descriptions, not just "file.py:45"
        # Look for entries with at least 10 chars of description after file/line info
        entries_with_context = len(re.findall(r'-\s*\[[ x]\].*?[:\-].*?\w{8,}', content, re.IGNORECASE))
        
        if entries_with_context >= 6:
            criteria_scores["context_included"] = 15
            feedback_parts.append(f"✅ {entries_with_context} entries include meaningful context/descriptions")
        elif entries_with_context >= 3:
            criteria_scores["context_included"] = 10
            feedback_parts.append(f"⚠️ {entries_with_context} entries include context (needs more detail)")
        else:
            criteria_scores["context_included"] = 5
            feedback_parts.append(f"❌ Only {entries_with_context} entries include adequate context")
        
        # Criterion 6: No False Positives (10 points)
        false_positive_indicators = [
            'node_modules', 'venv', 'dist/', 'build/', '__pycache__',
            'package-lock.json', 'yarn.lock', '.git/'
        ]
        
        has_false_positives = any(indicator in content for indicator in false_positive_indicators)
        
        if not has_false_positives:
            criteria_scores["no_false_positives"] = 10
            feedback_parts.append("✅ No false positives from dependencies or build artifacts")
        else:
            criteria_scores["no_false_positives"] = 5
            feedback_parts.append("⚠️ May include false positives from non-source files")
        
        # Criterion 7: Organized by Severity (10 points)
        severity_keywords = ['critical', 'security', 'deferred', 'priority', 'urgent', 'minor', 'high', 'low']
        severity_mentions = sum(1 for keyword in severity_keywords if keyword.lower() in content.lower())
        
        # Also check for type-based organization (FIXME/HACK vs TODO vs XXX)
        has_fixme_section = bool(re.search(r'##.*fixme', content, re.IGNORECASE) or re.search(r'##.*hack', content, re.IGNORECASE))
        has_todo_section = bool(re.search(r'##.*todo', content, re.IGNORECASE) or re.search(r'##.*deferred', content, re.IGNORECASE))
        has_xxx_section = bool(re.search(r'##.*xxx', content, re.IGNORECASE) or re.search(r'##.*security', content, re.IGNORECASE))
        
        type_sections = sum([has_fixme_section, has_todo_section, has_xxx_section])
        
        if type_sections >= 2 or severity_mentions >= 2:
            criteria_scores["organized_by_severity"] = 10
            feedback_parts.append("✅ Document attempts severity/type categorization")
        elif type_sections >= 1 or severity_mentions >= 1:
            criteria_scores["organized_by_severity"] = 5
            feedback_parts.append("⚠️ Minimal severity categorization")
        else:
            criteria_scores["organized_by_severity"] = 0
            feedback_parts.append("❌ No severity categorization")
        
        # Calculate final score
        total_score = sum(criteria_scores.values())
        passed = total_score >= 70
        
        # Add detailed breakdown
        feedback_parts.append(f"\n📊 Score breakdown: File({criteria_scores['file_created']}/15) Structure({criteria_scores['proper_structure']}/15) Coverage({criteria_scores['sufficient_coverage']}/20) Accuracy({criteria_scores['accurate_references']}/15) Context({criteria_scores['context_included']}/15) NoFalsePos({criteria_scores['no_false_positives']}/10) Organized({criteria_scores['organized_by_severity']}/10)")
        
        # Overall assessment
        if passed:
            feedback_parts.append(f"✅ PASS: Comprehensive technical debt inventory ({total_score}/100)")
        else:
            feedback_parts.append(f"❌ FAIL: Incomplete or inaccurate inventory ({total_score}/100, need 70+)")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "criteria_scores": criteria_scores,
                "found_markers": found_count,
                "total_markers": len(expected_debt),
                "coverage_percent": round(coverage_percent, 1)
            }
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
