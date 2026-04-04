#!/usr/bin/env python3
"""
Verifier for Sync Forked Repository task
Checks git remote configuration and branch synchronization
"""

import sys
import os
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sync_forked_repository(traj, env_info, task_info):
    """
    Verify that forked repository was synced correctly.
    
    Checks:
    1. Upstream remote configured correctly
    2. Upstream branches fetched (upstream/main exists)
    3. Local main branch synchronized with upstream/main
    4. Feature branch rebased on updated main (2 commits ahead)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    temp_dir = tempfile.mkdtemp(prefix='git_sync_verify_')
    
    try:
        # Copy all exported git data
        files_to_copy = [
            "git_remotes_list.txt",
            "git_branches.txt",
            "git_log_graph.txt",
            "git_main_commit.txt",
            "git_upstream_main_commit.txt",
            "git_feature_commit.txt",
            "git_merge_base.txt",
            "git_feature_ahead.txt"
        ]
        
        local_files = {}
        for filename in files_to_copy:
            local_path = os.path.join(temp_dir, filename)
            try:
                copy_from_env(f"/tmp/{filename}", local_path)
                local_files[filename] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {filename}: {e}")
                # Create empty file for missing data
                with open(local_path, 'w') as f:
                    f.write("Missing")
                local_files[filename] = local_path
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # Criterion 1: Upstream remote configured correctly
        upstream_remote_ok = False
        if os.path.exists(local_files["git_remotes_list.txt"]):
            with open(local_files["git_remotes_list.txt"], 'r') as f:
                remotes_content = f.read()
            
            if 'upstream' in remotes_content and 'fastcache-upstream.git' in remotes_content:
                upstream_remote_ok = True
                criteria_passed += 1
                feedback_parts.append("✅ Upstream remote configured correctly")
            else:
                if 'upstream' not in remotes_content:
                    feedback_parts.append("❌ Upstream remote not found. Add with: git remote add upstream /tmp/git_remotes/fastcache-upstream.git")
                else:
                    feedback_parts.append("❌ Upstream remote points to wrong location")
        else:
            feedback_parts.append("❌ Could not verify remotes")
        
        # Criterion 2: Upstream branches fetched
        upstream_fetched = False
        if os.path.exists(local_files["git_branches.txt"]):
            with open(local_files["git_branches.txt"], 'r') as f:
                branches_content = f.read()
            
            if 'upstream/main' in branches_content or 'remotes/upstream/main' in branches_content:
                upstream_fetched = True
                criteria_passed += 1
                feedback_parts.append("✅ Upstream branches fetched successfully")
            else:
                feedback_parts.append("❌ Upstream not fetched. Run: git fetch upstream")
        else:
            feedback_parts.append("❌ Could not verify branches")
        
        # Criterion 3: Main branch synchronized with upstream
        main_synced = False
        if os.path.exists(local_files["git_main_commit.txt"]) and os.path.exists(local_files["git_upstream_main_commit.txt"]):
            with open(local_files["git_main_commit.txt"], 'r') as f:
                main_commit = f.read().strip()
            with open(local_files["git_upstream_main_commit.txt"], 'r') as f:
                upstream_main_commit = f.read().strip()
            
            if main_commit and upstream_main_commit and main_commit != "Failed" and upstream_main_commit != "Not fetched":
                if main_commit == upstream_main_commit:
                    main_synced = True
                    criteria_passed += 1
                    feedback_parts.append("✅ Local main synchronized with upstream/main")
                else:
                    feedback_parts.append("❌ Local main not synchronized. Update with: git checkout main && git merge upstream/main")
            else:
                if upstream_main_commit == "Not fetched":
                    feedback_parts.append("❌ Upstream not fetched yet")
                else:
                    feedback_parts.append("❌ Could not compare main branches")
        else:
            feedback_parts.append("❌ Could not verify main branch sync")
        
        # Criterion 4: Feature branch rebased on updated main
        feature_rebased = False
        if os.path.exists(local_files["git_merge_base.txt"]) and os.path.exists(local_files["git_main_commit.txt"]):
            with open(local_files["git_merge_base.txt"], 'r') as f:
                merge_base = f.read().strip()
            with open(local_files["git_main_commit.txt"], 'r') as f:
                main_commit = f.read().strip()
            
            # If feature is properly rebased, merge-base should equal main
            if merge_base and main_commit and merge_base == main_commit and merge_base != "Failed":
                # Check that feature has commits ahead
                if os.path.exists(local_files["git_feature_ahead.txt"]):
                    with open(local_files["git_feature_ahead.txt"], 'r') as f:
                        ahead_count = f.read().strip()
                    
                    try:
                        ahead = int(ahead_count)
                        if ahead >= 2:
                            feature_rebased = True
                            criteria_passed += 1
                            feedback_parts.append(f"✅ Feature branch rebased successfully ({ahead} commits ahead of main)")
                        else:
                            feedback_parts.append(f"❌ Feature commits missing after rebase (expected 2, found {ahead})")
                    except ValueError:
                        feedback_parts.append("❌ Could not verify feature commits")
                else:
                    feedback_parts.append("❌ Could not verify feature branch state")
            else:
                feedback_parts.append("❌ Feature branch not rebased on main. Run: git checkout feature/cache-invalidation && git rebase main")
        else:
            feedback_parts.append("❌ Could not verify feature branch rebase")
        
        # Additional check: Verify feature code still exists after rebase
        if feature_rebased:
            try:
                cache_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
                copy_from_env("/home/ga/workspace/fastcache/src/cache.py", cache_file.name)
                
                with open(cache_file.name, 'r') as f:
                    content = f.read()
                
                if 'def invalidate' not in content:
                    feedback_parts.append("⚠️ Warning: Feature code (invalidate method) missing after rebase")
                
                os.unlink(cache_file.name)
            except Exception as e:
                logger.warning(f"Could not verify feature code: {e}")
        
        # Calculate score and success
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed == total_criteria  # All criteria must pass
        
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
