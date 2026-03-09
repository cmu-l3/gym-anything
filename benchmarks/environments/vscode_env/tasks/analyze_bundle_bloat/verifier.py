#!/usr/bin/env python3
"""
Verifier for Bundle Size Analysis task
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bundle_analysis(traj, env_info, task_info):
    """
    Verify that bundle analysis was completed correctly.

    Checks:
    1. Bundle analyzer tool installed in package.json devDependencies
    2. BUNDLE_ANALYSIS.md file exists
    3. Report identifies at least 3 specific dependencies by name
    4. Report includes quantitative data (KB/MB or percentages)
    5. Report contains actionable recommendations
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='bundle_verify_')

    try:
        # Copy exported files
        package_json_local = os.path.join(temp_dir, "package.json")
        report_local = os.path.join(temp_dir, "BUNDLE_ANALYSIS.md")
        workspace_files_local = os.path.join(temp_dir, "workspace_files.txt")

        try:
            copy_from_env("/tmp/package.json", package_json_local)
            copy_from_env("/tmp/BUNDLE_ANALYSIS.md", report_local)
            copy_from_env("/tmp/workspace_files.txt", workspace_files_local)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy files: {str(e)}"}

        criteria_passed = 0
        feedback_parts = []

        # Criterion 1: Check if bundle analyzer tool is installed
        analyzer_found = False
        if os.path.exists(package_json_local) and os.path.getsize(package_json_local) > 0:
            try:
                with open(package_json_local, 'r') as f:
                    package_data = json.load(f)
                
                dev_deps = package_data.get('devDependencies', {})
                analyzer_tools = [
                    'webpack-bundle-analyzer',
                    'rollup-plugin-visualizer',
                    'source-map-explorer',
                    'bundle-analyzer'
                ]
                
                found_tools = [tool for tool in analyzer_tools if tool in dev_deps]
                if found_tools:
                    analyzer_found = True
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Bundle analyzer installed: {', '.join(found_tools)}")
                else:
                    feedback_parts.append(f"❌ No bundle analyzer found in devDependencies (checked: {', '.join(analyzer_tools)})")
            except json.JSONDecodeError:
                feedback_parts.append("❌ package.json is invalid JSON")
        else:
            feedback_parts.append("❌ package.json not found or empty")

        # Criterion 2: Check if BUNDLE_ANALYSIS.md exists and has content
        report_content = ""
        report_exists = False
        if os.path.exists(report_local) and os.path.getsize(report_local) > 10:
            with open(report_local, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
            
            if report_content.strip():
                report_exists = True
                criteria_passed += 1
                feedback_parts.append(f"✅ BUNDLE_ANALYSIS.md exists ({len(report_content)} bytes)")
            else:
                feedback_parts.append("❌ BUNDLE_ANALYSIS.md is empty")
        else:
            feedback_parts.append("❌ BUNDLE_ANALYSIS.md not found or too small")

        # Criterion 3: Check if report identifies at least 3 dependencies
        dependencies_found = 0
        if report_exists:
            # Look for common dependency names (case-insensitive)
            dependency_keywords = [
                'lodash', 'moment', 'chart', 'chart.js', 'chartjs',
                'react-dom', 'react', 'axios', 'date-fns', 'core-js',
                '@babel', 'webpack', 'tslib', 'vue', 'angular',
                'jquery', 'bootstrap', 'material', 'antd',
                'styled-component', 'emotion', 'polyfill'
            ]
            
            report_lower = report_content.lower()
            unique_deps_found = set()
            
            for kw in dependency_keywords:
                # Use word boundaries to avoid false positives
                pattern = r'\b' + re.escape(kw.lower()) + r'\b'
                if re.search(pattern, report_lower):
                    unique_deps_found.add(kw)
            
            dependencies_found = len(unique_deps_found)
            
            if dependencies_found >= 3:
                criteria_passed += 1
                feedback_parts.append(f"✅ Report identifies {dependencies_found} dependencies")
            else:
                feedback_parts.append(f"❌ Report only identifies {dependencies_found} dependencies (need 3+)")

        # Criterion 4: Check for quantitative data (sizes, percentages)
        has_quantitative_data = False
        if report_exists:
            # Look for size patterns: "250KB", "1.2 MB", "35%", etc.
            size_patterns = [
                r'\d+\.?\d*\s*[KM]B',        # e.g., "250KB", "1.2 MB"
                r'\d+\.?\d*\s*kb',            # e.g., "250kb"
                r'\d+\.?\d*\s*mb',            # e.g., "1.2mb"
                r'\d+\.?\d*\s*%',             # e.g., "35%", "12.5%"
                r'\d+\s*kilobytes',           # e.g., "250 kilobytes"
                r'\d+\s*megabytes',           # e.g., "2 megabytes"
            ]
            
            matches_found = 0
            for pattern in size_patterns:
                matches = re.findall(pattern, report_content, re.IGNORECASE)
                matches_found += len(matches)
            
            if matches_found >= 2:  # At least 2 size mentions
                has_quantitative_data = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Report includes quantitative data ({matches_found} size references)")
            else:
                feedback_parts.append("❌ Report lacks quantitative size data (KB/MB/percentages)")

        # Criterion 5: Check for actionable recommendations
        has_recommendations = False
        if report_exists:
            recommendation_keywords = [
                'remove', 'replace', 'alternative', 'tree-shak', 'tree shak',
                'code-split', 'code split', 'lazy', 'dynamic import',
                'optimize', 'reduce', 'consider', 'recommend', 'suggestion',
                'switch', 'migrate', 'use instead', 'lighter', 'smaller',
                'defer', 'async', 'bundle', 'minif'
            ]
            
            report_lower = report_content.lower()
            found_recommendations = [kw for kw in recommendation_keywords if kw in report_lower]
            
            if found_recommendations:
                has_recommendations = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Report includes recommendations")
            else:
                feedback_parts.append("❌ Report lacks actionable optimization recommendations")

        # Calculate score
        score = int((criteria_passed / 5) * 100)
        passed = score >= 75

        # Additional debugging info if task failed
        if not passed and os.path.exists(workspace_files_local):
            with open(workspace_files_local, 'r') as f:
                workspace_listing = f.read()
            if 'BUNDLE_ANALYSIS.md' in workspace_listing:
                feedback_parts.append("⚠️ Note: File exists in workspace but may not have been exported properly")

        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
