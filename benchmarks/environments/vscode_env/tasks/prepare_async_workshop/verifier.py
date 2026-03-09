#!/usr/bin/env python3
"""
Verifier for Prepare Async Workshop task
Checks that teaching workspace is properly set up with progressive examples
"""

import sys
import os
import json
import re
import logging
import tempfile
import shutil
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import (
    read_file_content,
    check_file_exists,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_async_workshop(traj, env_info, task_info):
    """
    Verify that async workshop workspace was properly prepared.
    
    Checks:
    1. All required files exist (9 files)
    2. VSCode settings.json with teaching optimizations
    3. launch.json with Node.js debug configuration
    4. Callback hell example with nested callbacks and comments
    5. Async/await example with proper syntax
    6. Mock API with Promises and setTimeout
    7. README with substantial teaching content
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    workshop_dir = "/home/ga/workshop"
    temp_dir = tempfile.mkdtemp(prefix='workshop_verify_')
    
    try:
        score = 0.0
        max_score = 10.0
        issues = []
        
        # Check 1: Required files exist (2 points)
        required_files = [
            "01-callbacks-problem.js",
            "02-callbacks-fixed.js",
            "03-promises-basics.js",
            "04-async-await.js",
            "05-error-handling.js",
            "06-parallel-async.js",
            "mock-api.js",
            "README.md",
            "package.json"
        ]
        
        local_files = {}
        missing_files = []
        
        for filename in required_files:
            container_path = f"{workshop_dir}/{filename}"
            local_path = os.path.join(temp_dir, filename)
            
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
                    local_files[filename] = local_path
                else:
                    missing_files.append(filename)
            except Exception as e:
                logger.debug(f"Failed to copy {filename}: {e}")
                missing_files.append(filename)
        
        if not missing_files:
            score += 2.0
        else:
            issues.append(f"Missing files: {', '.join(missing_files[:3])}" + (f" and {len(missing_files)-3} more" if len(missing_files) > 3 else ""))
        
        # Check 2: VSCode settings.json exists and has teaching optimizations (2 points)
        vscode_dir = os.path.join(temp_dir, ".vscode")
        os.makedirs(vscode_dir, exist_ok=True)
        
        settings_path = os.path.join(vscode_dir, "settings.json")
        try:
            copy_from_env(f"{workshop_dir}/.vscode/settings.json", settings_path)
            
            if os.path.exists(settings_path) and os.path.getsize(settings_path) > 0:
                with open(settings_path, 'r') as f:
                    settings = json.load(f)
                
                settings_score = 0
                
                # Check font size (for projection)
                font_size = settings.get("editor.fontSize", 0)
                if font_size >= 16:
                    settings_score += 0.8
                else:
                    issues.append(f"Font too small: {font_size} (need >= 16 for projection)")
                
                # Check for accessible theme
                theme = settings.get("workbench.colorTheme", "")
                if any(keyword in theme for keyword in ["High Contrast", "Light", "Dark"]):
                    settings_score += 0.6
                else:
                    issues.append("Theme not optimized for accessibility")
                
                # Check minimap disabled
                if not settings.get("editor.minimap.enabled", True):
                    settings_score += 0.6
                
                score += settings_score
            else:
                issues.append("settings.json missing or empty")
        except Exception as e:
            logger.debug(f"Failed to verify settings.json: {e}")
            issues.append("settings.json not found")
        
        # Check 3: launch.json with Node.js debug config (1.5 points)
        launch_path = os.path.join(vscode_dir, "launch.json")
        try:
            copy_from_env(f"{workshop_dir}/.vscode/launch.json", launch_path)
            
            if os.path.exists(launch_path) and os.path.getsize(launch_path) > 0:
                with open(launch_path, 'r') as f:
                    launch_config = json.load(f)
                
                configs = launch_config.get("configurations", [])
                has_node_config = any(c.get("type") == "node" for c in configs)
                
                if has_node_config:
                    score += 1.5
                else:
                    issues.append("launch.json missing Node.js configuration")
                    score += 0.5  # File exists but wrong content
            else:
                issues.append("launch.json missing")
        except Exception as e:
            logger.debug(f"Failed to verify launch.json: {e}")
            issues.append("launch.json not found")
        
        # Check 4: Callback hell example (1.5 points)
        if "01-callbacks-problem.js" in local_files:
            content = read_file_content(local_files["01-callbacks-problem.js"])
            
            callback_score = 0
            
            # Look for nested callbacks (multiple closing patterns)
            nesting_pattern = r'\}\s*\)|\)\s*\{|\}\s*,\s*function|\)\s*=>'
            nesting_count = len(re.findall(nesting_pattern, content))
            
            # Alternative: count function keywords inside functions
            function_patterns = content.count('function(') + content.count('function (') + content.count('=>')
            
            if nesting_count >= 3 or function_patterns >= 2:
                callback_score += 0.8
            else:
                issues.append("Callback example not sufficiently nested")
            
            # Look for explanatory comments
            has_explanation = any(keyword in content.lower() for keyword in [
                'callback hell', 'nested', 'pyramid', 'callback', 'hell'
            ])
            
            if has_explanation:
                callback_score += 0.7
            else:
                issues.append("Callback example lacks explanatory comments")
            
            score += callback_score
        
        # Check 5: Async/await example (1.5 points)
        if "04-async-await.js" in local_files:
            content = read_file_content(local_files["04-async-await.js"])
            
            async_score = 0
            
            # Check for async/await syntax
            has_async = 'async' in content and 'await' in content
            
            if has_async:
                async_score += 1.0
            else:
                issues.append("async/await example missing async/await syntax")
            
            # Check for comments
            has_comments = '//' in content or '/*' in content
            
            if has_comments:
                async_score += 0.5
            else:
                issues.append("async/await example lacks comments")
            
            score += async_score
        
        # Check 6: Mock API with Promises and setTimeout (1.0 point)
        if "mock-api.js" in local_files:
            content = read_file_content(local_files["mock-api.js"])
            
            mock_score = 0
            
            # Check for Promise or async functions
            has_promises = 'Promise' in content or 'async function' in content or 'async ' in content
            
            if has_promises:
                mock_score += 0.6
            else:
                issues.append("Mock API doesn't use Promises")
            
            # Check for setTimeout (simulating async delay)
            has_timeout = 'setTimeout' in content
            
            if has_timeout:
                mock_score += 0.4
            else:
                issues.append("Mock API should use setTimeout for delays")
            
            score += mock_score
        
        # Check 7: README with teaching content (1.0 point)
        if "README.md" in local_files:
            content = read_file_content(local_files["README.md"])
            
            readme_score = 0
            
            # Check for teaching keywords
            has_objectives = any(keyword in content.lower() for keyword in [
                'objective', 'goal', 'workshop', 'learn'
            ])
            
            has_instructions = any(keyword in content.lower() for keyword in [
                'run', 'execute', 'instruction', 'step'
            ])
            
            is_substantial = len(content) > 150
            
            if has_objectives and has_instructions:
                readme_score += 0.6
            elif has_objectives or has_instructions:
                readme_score += 0.3
            
            if is_substantial:
                readme_score += 0.4
            else:
                issues.append("README too brief for workshop guide")
            
            score += readme_score
        
        # Normalize score
        final_score = score / max_score
        
        # Generate feedback
        if final_score >= 0.9:
            reward = 1.0
            feedback = "✅ Workshop environment excellently prepared! Students will have a clear, accessible learning path with progressive examples."
        elif final_score >= 0.75:
            reward = 0.8
            feedback = f"✅ Workshop mostly ready ({int(final_score*100)}%), minor improvements: " + " | ".join(issues[:2])
        elif final_score >= 0.5:
            reward = 0.5
            feedback = f"⚠️ Workshop partially prepared ({int(final_score*100)}%): " + " | ".join(issues[:3])
        else:
            reward = 0.0
            feedback = f"❌ Workshop inadequately prepared ({int(final_score*100)}%): " + " | ".join(issues[:4])
        
        return {
            "passed": reward >= 0.9,
            "score": int(final_score * 100),
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
