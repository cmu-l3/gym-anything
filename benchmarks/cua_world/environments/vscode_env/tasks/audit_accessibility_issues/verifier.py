#!/usr/bin/env python3
"""
Verifier for Accessibility Audit task
"""

import sys
import os
import logging
import tempfile
import shutil
import json
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content, check_file_exists

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_violations_from_report(report_content):
    """
    Extract file paths and line numbers mentioned in the audit report.
    Returns dict with 'files' (set of mentioned files) and 'locations' (list of tuples)
    """
    files_mentioned = set()
    locations = []
    
    # Pattern to match file paths (various formats)
    # src/components/UserProfile.jsx
    # src/pages/ContactForm.jsx:7
    # UserProfile.jsx line 7
    file_patterns = [
        r'src/[\w/]+\.(?:jsx|tsx|html)',  # Full paths
        r'[\w]+\.(?:jsx|tsx|html)',  # Just filenames
    ]
    
    for pattern in file_patterns:
        matches = re.finditer(pattern, report_content)
        for match in matches:
            filepath = match.group(0)
            # Normalize to include src/ if missing
            if not filepath.startswith('src/'):
                # Try to guess the full path from context
                files_mentioned.add(filepath)
            else:
                files_mentioned.add(filepath)
    
    # Pattern to extract line numbers near file mentions
    # "UserProfile.jsx:7" or "UserProfile.jsx line 7" or "line 7"
    line_number_patterns = [
        r'(src/[\w/]+\.(?:jsx|tsx|html)):(\d+)',
        r'([\w]+\.(?:jsx|tsx|html))\s+(?:line|Line|LINE)\s+(\d+)',
        r'(?:line|Line|LINE)\s+(\d+)',
    ]
    
    for pattern in line_number_patterns:
        matches = re.finditer(pattern, report_content)
        for match in matches:
            groups = match.groups()
            if len(groups) == 2:
                locations.append((groups[0], int(groups[1])))
            elif len(groups) == 1:
                locations.append((None, int(groups[0])))
    
    return {
        'files': files_mentioned,
        'locations': locations,
        'raw_content': report_content
    }


def check_false_positives(report_content):
    """
    Check if report incorrectly flags decorative images (alt="") as violations.
    Returns count of false positives found.
    """
    false_positive_count = 0
    
    # Check if DecorativeImages.jsx is mentioned as having violations
    decorative_file_pattern = r'DecorativeImages\.jsx'
    
    # Split report into sections to see if DecorativeImages is in violation section
    lines = report_content.split('\n')
    in_violation_section = False
    
    for line in lines:
        # Check if we're in a section listing violations
        if any(keyword in line.lower() for keyword in ['missing alt', 'violation', 'issue', 'problem']):
            in_violation_section = True
        elif line.startswith('#'):  # New section
            if 'summary' in line.lower() or 'recommendation' in line.lower():
                in_violation_section = False
        
        if in_violation_section and re.search(decorative_file_pattern, line):
            # If DecorativeImages.jsx is mentioned in violation context, it might be false positive
            # But we need to be careful - check if the context suggests it's a violation
            if not any(word in line.lower() for word in ['correct', 'valid', 'good', 'proper']):
                false_positive_count += 1
    
    return false_positive_count


def load_actual_violations(temp_dir):
    """
    Load the actual violations from source files.
    Returns dict with violations by category.
    """
    violations_key_path = os.path.join(temp_dir, '.violations_key.json')
    
    if os.path.exists(violations_key_path):
        with open(violations_key_path, 'r') as f:
            return json.load(f)
    
    # Fallback: manually scan files if key not available
    violations = {
        'missing_alt': [],
        'unlabeled_buttons': [],
        'unlabeled_inputs': [],
        'decorative_images': []
    }
    
    src_dir = os.path.join(temp_dir, 'src')
    if not os.path.exists(src_dir):
        return violations
    
    # Scan for violations in source files
    for root, dirs, files in os.walk(src_dir):
        for file in files:
            if file.endswith(('.jsx', '.tsx', '.html')):
                filepath = os.path.join(root, file)
                rel_path = os.path.relpath(filepath, temp_dir)
                
                content = read_file_content(filepath)
                lines = content.split('\n')
                
                for i, line in enumerate(lines, 1):
                    # Check for img without alt
                    if '<img' in line and 'alt=' not in line:
                        violations['missing_alt'].append({
                            'file': rel_path,
                            'line': i,
                            'pattern': line.strip()[:50]
                        })
                    
                    # Check for buttons without aria-label or text content (simplified)
                    if '<button' in line and 'aria-label' not in line:
                        if '/>' in line or ('</button>' not in line and i < len(lines)):
                            violations['unlabeled_buttons'].append({
                                'file': rel_path,
                                'line': i,
                                'pattern': line.strip()[:50]
                            })
                    
                    # Check for inputs without labels (simplified)
                    if '<input' in line and 'aria-label' not in line and 'id=' not in line:
                        violations['unlabeled_inputs'].append({
                            'file': rel_path,
                            'line': i,
                            'pattern': line.strip()[:50]
                        })
                    
                    # Track decorative images (correct usage)
                    if '<img' in line and 'alt=""' in line:
                        violations['decorative_images'].append({
                            'file': rel_path,
                            'line': i,
                            'pattern': line.strip()[:50]
                        })
    
    return violations


def verify_accessibility_audit(traj, env_info, task_info):
    """
    Verify that accessibility audit was conducted correctly.
    
    Scoring criteria:
    1. Report exists and has reasonable content (20 points)
    2. Report structure (has sections, categorization) (15 points)
    3. Coverage - identifies real violations (35 points)
    4. Accuracy - no false positives (decorative images) (20 points)
    5. Specificity - includes file paths and/or line numbers (10 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='accessibility_verify_')
    
    try:
        # Copy the audit report
        report_path = "/home/ga/workspace/accessibility_audit/ACCESSIBILITY_AUDIT.md"
        local_report = os.path.join(temp_dir, "ACCESSIBILITY_AUDIT.md")
        
        try:
            copy_from_env(report_path, local_report)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Audit report not found at {report_path}"
            }
        
        if not os.path.exists(local_report) or os.path.getsize(local_report) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Audit report is empty or not found"
            }
        
        # Read report content
        report_content = read_file_content(local_report)
        
        if len(report_content.strip()) < 100:
            return {
                "passed": False,
                "score": 20,
                "feedback": "❌ Report too short (less than 100 characters)"
            }
        
        # Copy source files and violations key for verification
        try:
            copy_from_env("/tmp/accessibility_audit_export/.violations_key.json", 
                         os.path.join(temp_dir, ".violations_key.json"))
        except:
            logger.warning("Could not copy violations key")
        
        # Copy source files
        src_files = [
            "src/components/UserProfile.jsx",
            "src/components/ProductCard.jsx",
            "src/pages/ContactForm.jsx",
            "src/components/DecorativeImages.jsx",
            "src/pages/Gallery.jsx"
        ]
        
        for src_file in src_files:
            try:
                local_path = os.path.join(temp_dir, src_file)
                os.makedirs(os.path.dirname(local_path), exist_ok=True)
                copy_from_env(f"/home/ga/workspace/accessibility_audit/{src_file}", local_path)
            except:
                logger.warning(f"Could not copy {src_file}")
        
        # Load actual violations
        actual_violations = load_actual_violations(temp_dir)
        
        # Parse reported violations
        reported = parse_violations_from_report(report_content)
        
        # Scoring
        score = 0
        feedback_parts = []
        
        # Criterion 1: Report exists and has content (20 points)
        score += 20
        feedback_parts.append(f"✅ Report exists ({len(report_content)} chars)")
        
        # Criterion 2: Report structure (15 points)
        structure_score = 0
        has_headers = len(re.findall(r'^#+\s+', report_content, re.MULTILINE)) >= 2
        has_lists = '-' in report_content or '*' in report_content or re.search(r'^\d+\.', report_content, re.MULTILINE)
        has_summary = bool(re.search(r'summary|total|count', report_content, re.I))
        
        if has_headers:
            structure_score += 5
        if has_lists:
            structure_score += 5
        if has_summary:
            structure_score += 5
        
        score += structure_score
        if structure_score >= 10:
            feedback_parts.append(f"✅ Good structure (headers, lists, summary)")
        else:
            feedback_parts.append(f"⚠️ Report structure could be improved")
        
        # Criterion 3: Coverage - identifies real violations (35 points)
        total_violations = (len(actual_violations['missing_alt']) + 
                          len(actual_violations['unlabeled_buttons']) + 
                          len(actual_violations['unlabeled_inputs']))
        
        # Count how many violation categories are mentioned
        mentions_alt = bool(re.search(r'alt|image|img', report_content, re.I))
        mentions_buttons = bool(re.search(r'button|aria-label', report_content, re.I))
        mentions_inputs = bool(re.search(r'input|label|form', report_content, re.I))
        
        categories_mentioned = sum([mentions_alt, mentions_buttons, mentions_inputs])
        
        # Check specific file mentions
        files_with_violations = {
            'UserProfile.jsx', 'ProductCard.jsx', 'ContactForm.jsx', 'Gallery.jsx'
        }
        files_mentioned_in_report = reported['files']
        
        # Count how many violation files are mentioned
        violation_files_found = sum(1 for f in files_with_violations 
                                   if any(f in mentioned for mentioned in files_mentioned_in_report))
        
        coverage_score = 0
        if categories_mentioned >= 2:
            coverage_score += 15
        if violation_files_found >= 2:
            coverage_score += 10
        if violation_files_found >= 3:
            coverage_score += 10
        
        score += coverage_score
        feedback_parts.append(f"✅ Coverage: {categories_mentioned}/3 violation types, "
                            f"{violation_files_found}/4 files identified")
        
        # Criterion 4: Accuracy - no false positives (20 points)
        false_positives = check_false_positives(report_content)
        decorative_mentioned = 'DecorativeImages' in report_content or 'decorative' in report_content.lower()
        
        accuracy_score = 20
        if false_positives > 0:
            accuracy_score -= 10
            feedback_parts.append(f"⚠️ Possible false positives detected (decorative images)")
        elif decorative_mentioned:
            # If they mentioned decorative images in a positive way, that's good
            if any(word in report_content.lower() for word in ['correct', 'valid', 'properly']):
                accuracy_score = 20
                feedback_parts.append(f"✅ Correctly distinguished decorative images")
        else:
            accuracy_score = 20
            feedback_parts.append(f"✅ No false positives detected")
        
        score += accuracy_score
        
        # Criterion 5: Specificity - includes file paths and/or line numbers (10 points)
        has_file_paths = len(reported['files']) > 0
        has_line_numbers = len(reported['locations']) > 0
        
        specificity_score = 0
        if has_file_paths:
            specificity_score += 5
        if has_line_numbers:
            specificity_score += 5
        
        score += specificity_score
        if specificity_score >= 5:
            feedback_parts.append(f"✅ Includes specific locations ({len(reported['files'])} files mentioned)")
        else:
            feedback_parts.append(f"⚠️ Missing specific file paths or line numbers")
        
        # Determine pass/fail
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": min(100, score),
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
