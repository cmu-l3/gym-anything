#!/usr/bin/env python3
"""
Verifier for Configure Monorepo Workspace task
"""

import sys
import os
import logging
import tempfile
import json
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import copy_and_parse_json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_monorepo_workspace(traj, env_info, task_info):
    """
    Verify that VSCode monorepo workspace was configured correctly.
    
    Checks 6 criteria (need 5+ to pass):
    1. Workspace settings exist (.vscode/settings.json)
    2. TypeScript workspace mode configured
    3. Search exclusions include node_modules
    4. Watcher exclusions configured
    5. TypeScript project references in root tsconfig
    6. Composite mode enabled in at least one package
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='monorepo_verify_')
    
    try:
        score = 0
        max_score = 6
        criteria_met = []
        feedback_parts = []
        
        # Criterion 1: Check workspace settings exist
        settings_path = "/tmp/workspace_settings.json"
        settings_local = os.path.join(temp_dir, "settings.json")
        
        try:
            copy_from_env(settings_path, settings_local)
        except Exception as e:
            logger.warning(f"Failed to copy workspace settings: {e}")
        
        settings = {}
        if os.path.exists(settings_local) and os.path.getsize(settings_local) > 0:
            try:
                with open(settings_local, 'r') as f:
                    settings = json.load(f)
                if settings and len(settings) > 0:
                    score += 1
                    criteria_met.append("workspace_settings_exist")
                    feedback_parts.append("✅ Workspace settings file exists")
                else:
                    feedback_parts.append("❌ Workspace settings file is empty")
            except json.JSONDecodeError:
                feedback_parts.append("❌ Workspace settings file is not valid JSON")
        else:
            feedback_parts.append("❌ Workspace settings file not found")
        
        # Criterion 2: Check TypeScript workspace configuration
        if settings:
            ts_keys = [
                "typescript.tsserver.experimental.enableProjectDiagnostics",
                "typescript.preferences.preferTypeOnlyAutoImports",
                "typescript.enablePromptUseWorkspaceTsdk",
                "typescript.tsdk"
            ]
            has_ts_config = any(key in settings for key in ts_keys)
            
            if has_ts_config:
                score += 1
                criteria_met.append("typescript_workspace_configured")
                found_keys = [k for k in ts_keys if k in settings]
                feedback_parts.append(f"✅ TypeScript workspace mode configured ({', '.join(found_keys)})")
            else:
                feedback_parts.append("❌ TypeScript workspace configuration not found")
        
        # Criterion 3: Check search exclusions
        if settings and "search.exclude" in settings:
            search_exclude = settings["search.exclude"]
            if isinstance(search_exclude, dict):
                has_node_modules = any("node_modules" in pattern for pattern in search_exclude.keys())
                if has_node_modules:
                    score += 1
                    criteria_met.append("search_exclusions_set")
                    feedback_parts.append("✅ Search exclusions include node_modules")
                else:
                    feedback_parts.append("❌ Search exclusions don't include node_modules")
            else:
                feedback_parts.append("❌ search.exclude is not properly configured")
        else:
            feedback_parts.append("❌ No search exclusions configured")
        
        # Criterion 4: Check watcher exclusions
        if settings and "files.watcherExclude" in settings:
            watcher_exclude = settings["files.watcherExclude"]
            if isinstance(watcher_exclude, dict):
                has_node_modules = any("node_modules" in pattern for pattern in watcher_exclude.keys())
                if has_node_modules:
                    score += 1
                    criteria_met.append("watcher_exclusions_set")
                    feedback_parts.append("✅ File watcher exclusions configured")
                else:
                    feedback_parts.append("❌ Watcher exclusions don't include node_modules")
            else:
                feedback_parts.append("❌ files.watcherExclude is not properly configured")
        else:
            feedback_parts.append("❌ No file watcher exclusions configured")
        
        # Criterion 5: Check TypeScript project references in root tsconfig
        root_tsconfig_path = "/tmp/root_tsconfig.json"
        root_tsconfig_local = os.path.join(temp_dir, "root_tsconfig.json")
        
        try:
            copy_from_env(root_tsconfig_path, root_tsconfig_local)
        except Exception as e:
            logger.warning(f"Failed to copy root tsconfig: {e}")
        
        if os.path.exists(root_tsconfig_local) and os.path.getsize(root_tsconfig_local) > 0:
            try:
                with open(root_tsconfig_local, 'r') as f:
                    root_tsconfig = json.load(f)
                
                if "references" in root_tsconfig:
                    refs = root_tsconfig["references"]
                    if isinstance(refs, list) and len(refs) >= 2:
                        score += 1
                        criteria_met.append("typescript_project_references")
                        feedback_parts.append(f"✅ TypeScript project references configured ({len(refs)} packages)")
                    else:
                        feedback_parts.append(f"❌ Project references found but insufficient ({len(refs) if isinstance(refs, list) else 0} < 2)")
                else:
                    feedback_parts.append("❌ No TypeScript project references found")
            except json.JSONDecodeError:
                feedback_parts.append("❌ Root tsconfig is not valid JSON")
        else:
            feedback_parts.append("❌ Root tsconfig not found or empty")
        
        # Criterion 6: Check composite mode in at least one package
        package_names = ['shared-utils', 'ui-components', 'api-client', 'backend']
        composite_found = False
        composite_packages = []
        
        for pkg_name in package_names:
            pkg_tsconfig_path = f"/tmp/package_tsconfigs/{pkg_name}_tsconfig.json"
            pkg_tsconfig_local = os.path.join(temp_dir, f"{pkg_name}_tsconfig.json")
            
            try:
                copy_from_env(pkg_tsconfig_path, pkg_tsconfig_local)
                
                if os.path.exists(pkg_tsconfig_local) and os.path.getsize(pkg_tsconfig_local) > 0:
                    with open(pkg_tsconfig_local, 'r') as f:
                        pkg_tsconfig = json.load(f)
                    
                    compiler_options = pkg_tsconfig.get("compilerOptions", {})
                    if compiler_options.get("composite") is True:
                        composite_found = True
                        composite_packages.append(pkg_name)
            except Exception as e:
                logger.debug(f"Could not check {pkg_name} tsconfig: {e}")
        
        if composite_found:
            score += 1
            criteria_met.append("composite_mode_enabled")
            feedback_parts.append(f"✅ Composite mode enabled in: {', '.join(composite_packages)}")
        else:
            feedback_parts.append("❌ No package has composite mode enabled")
        
        # Calculate final score and pass/fail
        final_score = int((score / max_score) * 100)
        passed = score >= 5  # Need 5 out of 6 criteria
        
        feedback = " | ".join(feedback_parts)
        
        result = {
            "passed": passed,
            "score": final_score,
            "feedback": feedback,
            "criteria_met": criteria_met,
            "total_criteria": f"{score}/{max_score}"
        }
        
        logger.info(f"Verification result: {result}")
        return result
    
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
