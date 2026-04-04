#!/usr/bin/env python3
"""
Verifier for diagnose_editor_slowdown@1 task
Checks that user properly diagnosed and mitigated VSCode performance issues
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil
from typing import Tuple, Dict, Any, List

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_performance_optimization(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that performance optimization was successful
    
    Checks 4 criteria (each worth 25%):
    1. Deprecated extensions disabled (Bracket Pair Colorizer removed)
    2. Performance settings configured (watchers, search exclusions)
    3. GitLens optimized (disabled or features turned off)
    4. Documentation created (PERFORMANCE_NOTES.md)
    
    Returns:
        Dict with passed, score, and feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "ERROR: Copy function not available"
        }
    
    feedback = {
        "extensions_cleaned": False,
        "settings_configured": False,
        "gitlens_optimized": False,
        "documentation_created": False,
        "details": []
    }
    
    temp_dir = tempfile.mkdtemp(prefix='vscode_perf_verify_')
    
    try:
        # Copy exported files
        files_to_copy = {
            "/tmp/workspace_settings.json": "workspace_settings.json",
            "/tmp/user_settings.json": "user_settings.json",
            "/tmp/PERFORMANCE_NOTES.md": "PERFORMANCE_NOTES.md",
            "/tmp/extension_folders.txt": "extension_folders.txt",
            "/tmp/installed_extensions.txt": "installed_extensions.txt"
        }
        
        local_files = {}
        for container_path, local_name in files_to_copy.items():
            local_path = os.path.join(temp_dir, local_name)
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[local_name] = local_path
                else:
                    logger.warning(f"File {container_path} not found or empty")
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")
        
        if not local_files:
            return {
                "passed": False,
                "score": 0,
                "feedback": "ERROR: Could not copy any verification files"
            }
        
        # Check 1: Verify deprecated extensions are removed/disabled
        ext_check = check_extensions_removed(local_files, feedback)
        
        # Check 2: Verify performance settings configured
        settings_check = check_performance_settings(local_files, feedback)
        
        # Check 3: Verify GitLens optimization
        gitlens_check = check_gitlens_optimization(local_files, feedback)
        
        # Check 4: Verify documentation exists
        docs_check = check_documentation(local_files, feedback)
        
        # Calculate score
        criteria_passed = sum([ext_check, settings_check, gitlens_check, docs_check])
        score = int((criteria_passed / 4.0) * 100)
        passed = score >= 75  # Need 3 out of 4 criteria
        
        feedback["extensions_cleaned"] = ext_check
        feedback["settings_configured"] = settings_check
        feedback["gitlens_optimized"] = gitlens_check
        feedback["documentation_created"] = docs_check
        
        feedback_text = " | ".join(feedback["details"])
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback_text
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"ERROR: Verification exception: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)


def check_extensions_removed(local_files: Dict[str, str], feedback: Dict) -> bool:
    """
    Check that Bracket Pair Colorizer is removed/disabled.
    This is the primary deprecated extension that MUST be removed.
    """
    try:
        extensions = []
        
        # Method 1: Check extension folders
        if "extension_folders.txt" in local_files:
            with open(local_files["extension_folders.txt"], 'r') as f:
                content = f.read()
                extensions.extend([line.strip().lower() for line in content.split('\n') if line.strip()])
        
        # Method 2: Check installed extensions list
        if "installed_extensions.txt" in local_files:
            with open(local_files["installed_extensions.txt"], 'r') as f:
                content = f.read()
                extensions.extend([line.strip().lower() for line in content.split('\n') if line.strip()])
        
        if not extensions:
            feedback["details"].append("❌ Extensions: Could not read extension list")
            return False
        
        # Check for Bracket Pair Colorizer (MUST be removed)
        bracket_colorizer_present = any(
            'bracket-pair-colorizer' in ext and 'coenraads' in ext
            for ext in extensions
        )
        
        if bracket_colorizer_present:
            feedback["details"].append(
                "❌ Extensions: Bracket Pair Colorizer (deprecated) still installed"
            )
            return False
        else:
            feedback["details"].append(
                "✅ Extensions: Bracket Pair Colorizer removed/disabled"
            )
            return True
    
    except Exception as e:
        logger.error(f"Error checking extensions: {e}")
        feedback["details"].append(f"❌ Extensions: Error checking - {str(e)}")
        return False


def check_performance_settings(local_files: Dict[str, str], feedback: Dict) -> bool:
    """
    Check that performance-critical settings are configured.
    Settings can be in workspace or user settings.
    """
    try:
        # Merge settings (workspace takes precedence over user)
        settings = {}
        
        # Load user settings first
        if "user_settings.json" in local_files:
            try:
                with open(local_files["user_settings.json"], 'r') as f:
                    settings.update(json.load(f))
            except json.JSONDecodeError:
                logger.warning("Could not parse user_settings.json")
        
        # Load workspace settings (overrides user)
        if "workspace_settings.json" in local_files:
            try:
                with open(local_files["workspace_settings.json"], 'r') as f:
                    workspace_settings = json.load(f)
                    settings.update(workspace_settings)
            except json.JSONDecodeError:
                logger.warning("Could not parse workspace_settings.json")
        
        if not settings:
            feedback["details"].append("❌ Settings: Could not load any settings")
            return False
        
        checks_passed = []
        
        # Check 1: files.watcherExclude
        watcher_exclude = settings.get("files.watcherExclude", {})
        if isinstance(watcher_exclude, dict):
            required_patterns = ["node_modules", "dist", ".git"]
            matched = [pattern for pattern in required_patterns 
                      if any(pattern in key for key in watcher_exclude.keys())]
            
            if len(matched) >= 2:  # At least 2 out of 3 patterns
                checks_passed.append("watcher")
            else:
                feedback["details"].append(
                    f"⚠️ Settings: files.watcherExclude incomplete (found {len(matched)}/3 patterns)"
                )
        else:
            feedback["details"].append("⚠️ Settings: files.watcherExclude not configured")
        
        # Check 2: search.exclude
        search_exclude = settings.get("search.exclude", {})
        if isinstance(search_exclude, dict):
            has_node_modules = any("node_modules" in key for key in search_exclude.keys())
            if has_node_modules:
                checks_passed.append("search")
            else:
                feedback["details"].append("⚠️ Settings: search.exclude missing node_modules")
        else:
            feedback["details"].append("⚠️ Settings: search.exclude not configured")
        
        # Check 3: files.exclude (optional but good)
        files_exclude = settings.get("files.exclude", {})
        if isinstance(files_exclude, dict):
            has_node_modules = any("node_modules" in key for key in files_exclude.keys())
            if has_node_modules:
                checks_passed.append("files")
        
        # Need at least 2 out of 3 checks to pass
        if len(checks_passed) >= 2:
            feedback["details"].append(
                f"✅ Settings: Performance exclusions configured ({', '.join(checks_passed)})"
            )
            return True
        else:
            feedback["details"].append(
                f"❌ Settings: Insufficient performance configuration (only {len(checks_passed)}/3)"
            )
            return False
    
    except Exception as e:
        logger.error(f"Error checking settings: {e}")
        feedback["details"].append(f"❌ Settings: Error checking - {str(e)}")
        return False


def check_gitlens_optimization(local_files: Dict[str, str], feedback: Dict) -> bool:
    """
    Check that GitLens is either removed or optimized for performance.
    """
    try:
        # Check if GitLens is still installed
        extensions = []
        
        if "extension_folders.txt" in local_files:
            with open(local_files["extension_folders.txt"], 'r') as f:
                extensions.extend([line.strip().lower() for line in f.readlines()])
        
        if "installed_extensions.txt" in local_files:
            with open(local_files["installed_extensions.txt"], 'r') as f:
                extensions.extend([line.strip().lower() for line in f.readlines()])
        
        gitlens_installed = any('gitlens' in ext for ext in extensions)
        
        # If GitLens is completely removed, that's optimal
        if not gitlens_installed:
            feedback["details"].append("✅ GitLens: Removed entirely (optimal)")
            return True
        
        # GitLens is still installed, check if expensive features are disabled
        settings = {}
        
        if "user_settings.json" in local_files:
            try:
                with open(local_files["user_settings.json"], 'r') as f:
                    settings.update(json.load(f))
            except:
                pass
        
        if "workspace_settings.json" in local_files:
            try:
                with open(local_files["workspace_settings.json"], 'r') as f:
                    settings.update(json.load(f))
            except:
                pass
        
        # Check if expensive features are disabled
        optimizations = []
        
        if settings.get("gitlens.currentLine.enabled") == False:
            optimizations.append("currentLine")
        
        if settings.get("gitlens.codeLens.enabled") == False:
            optimizations.append("codeLens")
        
        hover_setting = settings.get("gitlens.hovers.currentLine.over")
        if hover_setting == "line" or settings.get("gitlens.hovers.enabled") == False:
            optimizations.append("hovers")
        
        # Need at least 2 optimizations
        if len(optimizations) >= 2:
            feedback["details"].append(
                f"✅ GitLens: Optimized (disabled: {', '.join(optimizations)})"
            )
            return True
        else:
            feedback["details"].append(
                "❌ GitLens: Still has expensive features enabled (disable currentLine, codeLens, or hovers)"
            )
            return False
    
    except Exception as e:
        logger.error(f"Error checking GitLens: {e}")
        feedback["details"].append(f"❌ GitLens: Error checking - {str(e)}")
        return False


def check_documentation(local_files: Dict[str, str], feedback: Dict) -> bool:
    """
    Check that PERFORMANCE_NOTES.md was created and contains appropriate content.
    """
    try:
        if "PERFORMANCE_NOTES.md" not in local_files:
            feedback["details"].append("❌ Documentation: PERFORMANCE_NOTES.md not created")
            return False
        
        with open(local_files["PERFORMANCE_NOTES.md"], 'r') as f:
            content = f.read()
        
        if not content.strip():
            feedback["details"].append("❌ Documentation: PERFORMANCE_NOTES.md is empty")
            return False
        
        content_lower = content.lower()
        
        # Check minimum length
        if len(content) < 80:
            feedback["details"].append(
                f"❌ Documentation: Too brief ({len(content)} chars, need 80+)"
            )
            return False
        
        # Check for required terms
        has_extension = 'extension' in content_lower
        has_performance = 'performance' in content_lower
        
        # Check for structure (bullet points, multiple lines)
        bullet_count = content.count('-') + content.count('*') + content.count('•')
        line_count = content.count('\n')
        has_structure = bullet_count >= 3 or line_count >= 3
        
        issues = []
        if not has_extension:
            issues.append("missing 'extension'")
        if not has_performance:
            issues.append("missing 'performance'")
        if not has_structure:
            issues.append("needs more structure/bullets")
        
        if not issues:
            feedback["details"].append(
                f"✅ Documentation: Complete ({len(content)} chars, well-structured)"
            )
            return True
        else:
            feedback["details"].append(
                f"❌ Documentation: Incomplete ({', '.join(issues)})"
            )
            return False
    
    except Exception as e:
        logger.error(f"Error checking documentation: {e}")
        feedback["details"].append(f"❌ Documentation: Error checking - {str(e)}")
        return False
