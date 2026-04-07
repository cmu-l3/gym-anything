#!/usr/bin/env python3
"""
Verifier for fix_build_dependency_resolver task.

Constructs a local test harness from the extracted student code and runs targeted
test cases in a subprocess to independently verify all 5 bug fixes without relying
on the student's potentially modified `test_build.py`.
"""

import sys
import os
import json
import logging
import tempfile
import shutil
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# The independent test suite that will run against the extracted code
VERIFICATION_SCRIPT = """
import json
import sys

# Add current directory to path so module resolution works
sys.path.insert(0, ".")

try:
    from resolver.version import compare_versions
    from resolver.dependency_graph import DependencyGraph
    from resolver.constraint_solver import satisfies
    from scheduler.topo_sort import get_build_order
    from scheduler.cache_manager import CacheManager
except Exception as e:
    print(json.dumps({"error": f"Import failed: {e}"}))
    sys.exit(1)

results = {
    "bug1_version": False,
    "bug2_cycle": False,
    "bug3_constraint": False,
    "bug4_topo": False,
    "bug5_cache": False,
}

# Test 1: SemVer Comparison (Pre-release numeric sorting & release > prerelease)
try:
    # Use different values than test_build.py to prevent hardcoding
    numeric_ok = compare_versions("2.0.0-beta.11", "2.0.0-beta.2") == 1
    release_ok = compare_versions("3.1.0", "3.1.0-alpha.1") == 1
    if numeric_ok and release_ok:
        results["bug1_version"] = True
except Exception:
    pass

# Test 2: Cycle Detection (Diamond graph should not false positive)
try:
    g = DependencyGraph()
    g.add_edge("X", "Y")
    g.add_edge("X", "Z")
    g.add_edge("Y", "W")
    g.add_edge("Z", "W")
    if not g.has_cycle():
        # Ensure it actually detects real cycles too
        g.add_edge("W", "X")
        if g.has_cycle():
            results["bug2_cycle"] = True
except Exception:
    pass

# Test 3: Constraint Solver (Exclusive bounds)
try:
    if not satisfies("3.5.0", ">=3.0.0,<3.5.0"):
        results["bug3_constraint"] = True
except Exception:
    pass

# Test 4: Topo Sort (Dependencies before dependents)
try:
    g = DependencyGraph()
    g.add_edge("frontend", "backend")
    g.add_edge("backend", "db")
    o = get_build_order(g)
    if o.index("db") < o.index("backend") and o.index("backend") < o.index("frontend"):
        results["bug4_topo"] = True
except Exception:
    pass

# Test 5: Transitive Cache Invalidation
try:
    g = DependencyGraph()
    g.add_edge("A", "B")
    g.add_edge("B", "C")
    cm = CacheManager(g)
    cm.mark_built("A")
    cm.mark_built("B")
    cm.mark_built("C")
    cm.invalidate("C")
    if not cm.is_cached("A") and not cm.is_cached("B") and not cm.is_cached("C"):
        results["bug5_cache"] = True
except Exception:
    pass

print(json.dumps(results))
"""

def verify_build_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='buildsys_verify_')
    
    try:
        result_src = "/tmp/buildsys_result.json"
        local_result = os.path.join(temp_dir, "buildsys_result.json")
        
        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not extract code from environment: {e}"}

        with open(local_result, 'r', encoding='utf-8') as f:
            file_contents = json.load(f)

        # Reconstruct the python modules in the temp directory
        for rel_path, content in file_contents.items():
            if content and not content.startswith("ERROR:"):
                full_path = os.path.join(temp_dir, rel_path)
                os.makedirs(os.path.dirname(full_path), exist_ok=True)
                with open(full_path, "w", encoding='utf-8') as f:
                    f.write(content)
        
        # Ensure __init__.py files exist
        open(os.path.join(temp_dir, "resolver", "__init__.py"), "a").close()
        open(os.path.join(temp_dir, "scheduler", "__init__.py"), "a").close()

        # Write the verification script
        script_path = os.path.join(temp_dir, "run_verification.py")
        with open(script_path, "w", encoding='utf-8') as f:
            f.write(VERIFICATION_SCRIPT)

        # Execute the verification script securely in a subprocess
        proc = subprocess.run(
            [sys.executable, "run_verification.py"],
            cwd=temp_dir,
            capture_output=True,
            text=True,
            timeout=10
        )

        if proc.returncode != 0 and not proc.stdout.strip().startswith('{'):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Syntax or execution error in submitted files:\n{proc.stderr}"
            }

        try:
            results = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse test output: {proc.stdout}\n{proc.stderr}"
            }

        if "error" in results:
            return {
                "passed": False,
                "score": 0,
                "feedback": results["error"]
            }

        score = 0
        feedback_parts = []
        
        if results.get("bug1_version"):
            score += 20
            feedback_parts.append("[+] SemVer 2.0.0 comparison rules correctly implemented (20/20)")
        else:
            feedback_parts.append("[-] SemVer comparison still buggy (fails on numeric pre-releases or release vs prerelease) (0/20)")

        if results.get("bug2_cycle"):
            score += 20
            feedback_parts.append("[+] Cycle detection correctly handles diamond dependency graphs (20/20)")
        else:
            feedback_parts.append("[-] Cycle detection still produces false positives on diamond DAGs or misses real cycles (0/20)")

        if results.get("bug3_constraint"):
            score += 20
            feedback_parts.append("[+] Version constraint parser correctly handles exclusive upper bounds (20/20)")
        else:
            feedback_parts.append("[-] Constraint solver incorrectly includes boundary versions for `<` operators (0/20)")

        if results.get("bug4_topo"):
            score += 20
            feedback_parts.append("[+] Topological sort correctly orders dependencies before dependents (20/20)")
        else:
            feedback_parts.append("[-] Topological sort returns incorrect build ordering (0/20)")

        if results.get("bug5_cache"):
            score += 20
            feedback_parts.append("[+] Cache manager correctly invalidates transitive dependents (20/20)")
        else:
            feedback_parts.append("[-] Cache manager fails to propagate invalidations to downstream packages (0/20)")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)