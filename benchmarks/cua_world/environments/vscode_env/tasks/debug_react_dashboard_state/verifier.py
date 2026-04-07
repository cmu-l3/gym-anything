#!/usr/bin/env python3
"""
Verifier for the debug_react_dashboard_state task.

Evaluates fixes for 5 distinct React hooks anti-patterns:
1. LiveTicker: Stale closure in setInterval
2. OrderSearch: Fetch race condition
3. MetricsChart: Infinite loop due to recreated object reference
4. ResponsiveContainer: Memory leak (missing removeEventListener)
5. OrderList: Direct state mutation

Also uses VLM to ensure the agent actively used the IDE to edit files.
"""

import os
import json
import re
import logging
import tempfile

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────────
# Static Analysis Checks
# ──────────────────────────────────────────────────────────

def check_live_ticker(content):
    """
    Look for functional state update OR correct dependency array.
    Expected: setRevenue(prev => prev + 15) OR useEffect(..., [revenue])
    """
    if not content or "export default function LiveTicker" not in content:
        return False, "File missing or structure corrupted"
        
    functional_update = re.search(r'setRevenue\s*\(\s*(?:[a-zA-Z0-9_]+\s*=>|function\s*\()', content)
    revenue_in_deps = re.search(r'\}\s*,\s*\[[^\]]*\brevenue\b[^\]]*\]\s*\)', content)
    
    if functional_update or revenue_in_deps:
        return True, "Stale closure fixed (functional update or dependency added)"
    return False, "Still contains stale closure in setInterval"

def check_order_search(content):
    """
    Look for race condition prevention: AbortController or a boolean ignore flag.
    Expected: const controller = new AbortController() OR let ignore = false
    """
    if not content or "export default function OrderSearch" not in content:
        return False, "File missing or structure corrupted"

    has_abort_controller = "AbortController" in content and "signal" in content
    has_ignore_flag = re.search(r'\b(ignore|cancel|isMounted|active)\s*=\s*(true|false)', content) and \
                      re.search(r'return\s*\(\s*\)\s*=>', content)
                      
    if has_abort_controller or has_ignore_flag:
        return True, "Race condition prevented (AbortController or cleanup flag found)"
    return False, "Still vulnerable to fetch race condition"

def check_metrics_chart(content):
    """
    Look for memoization or external declaration.
    Expected: useMemo(() => ({theme: 'dark'}), []) OR config moved outside component OR removed from deps
    """
    if not content or "export default function MetricsChart" not in content:
        return False, "File missing or structure corrupted"
        
    has_usememo = "useMemo" in content and "theme: 'dark'" in content
    config_outside = re.search(r'const config = [^;]+;\s*export default function', content)
    removed_from_deps = re.search(r'\}\s*,\s*\[\s*data\s*\]\s*\)', content) # [data] instead of [data, config]
    
    if has_usememo or config_outside or removed_from_deps:
        return True, "Infinite loop prevented (Reference equality stabilized)"
    return False, "Still causes infinite effect loop"

def check_responsive_container(content):
    """
    Look for proper event listener cleanup.
    Expected: return () => window.removeEventListener('resize', handleResize)
    """
    if not content or "export default function ResponsiveContainer" not in content:
        return False, "File missing or structure corrupted"
        
    has_cleanup = re.search(r'return\s*(?:function)?\s*\(\s*\)\s*=>\s*\{?[^}]*removeEventListener\s*\(\s*[\'"]resize[\'"]', content)
    
    if has_cleanup:
        return True, "Memory leak plugged (removeEventListener added)"
    return False, "Still leaks memory (missing removeEventListener in cleanup)"

def check_order_list(content):
    """
    Look for immutable state updates.
    Expected: setOrders([...orders]) or orders.map(...)
    """
    if not content or "export default function OrderList" not in content:
        return False, "File missing or structure corrupted"
        
    # Check for array cloning/mapping before setOrders
    has_spread = re.search(r'\[\s*\.\.\.orders\s*\]', content) or re.search(r'\[\s*\.\.\.prev', content)
    has_map = re.search(r'orders\.map\s*\(', content)
    has_slice = re.search(r'orders\.slice\s*\(', content)
    has_from = re.search(r'Array\.from\s*\(\s*orders', content)
    
    if has_spread or has_map or has_slice or has_from:
        return True, "State immutability restored (Array cloned)"
    return False, "Still mutates state array directly"

# ──────────────────────────────────────────────────────────
# VLM Verification
# ──────────────────────────────────────────────────────────

VLM_PROMPT = """You are auditing a developer's workflow in VS Code.

Look at these trajectory frames of the agent completing the task.
Did the agent actively open, view, and modify React `.jsx` files in the VS Code editor?

Respond in JSON format:
{
    "edited_react_files": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what the agent was seen doing in the editor."
}
"""

def verify_react_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/react_dashboard_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    files = result.get("files", {})
    score = 0
    feedback_parts = []
    
    # 1. Evaluate Code Fixes (80 points total, 16 each)
    checks = [
        ("src/components/LiveTicker.jsx", check_live_ticker),
        ("src/components/OrderSearch.jsx", check_order_search),
        ("src/components/MetricsChart.jsx", check_metrics_chart),
        ("src/components/ResponsiveContainer.jsx", check_responsive_container),
        ("src/components/OrderList.jsx", check_order_list)
    ]
    
    files_modified = 0
    for path, check_fn in checks:
        file_data = files.get(path, {})
        content = file_data.get("content", "")
        modified = file_data.get("modified_during_task", False)
        
        passed, msg = check_fn(content)
        if passed and modified:
            score += 16
            files_modified += 1
            feedback_parts.append(f"✅ {path.split('/')[-1]}: {msg}")
        elif passed and not modified:
            feedback_parts.append(f"❌ {path.split('/')[-1]}: Fix present but file not modified during task (Cheating detected)")
        else:
            feedback_parts.append(f"❌ {path.split('/')[-1]}: {msg}")

    # 2. VLM Trajectory Verification (20 points)
    vlm_passed = False
    if query_vlm and traj:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("edited_react_files", False):
                    score += 20
                    vlm_passed = True
                    feedback_parts.append("✅ VLM: Verified active code editing in IDE")
                else:
                    feedback_parts.append("❌ VLM: Did not detect active React file editing")
            else:
                feedback_parts.append("⚠️ VLM query failed")
    else:
        feedback_parts.append("⚠️ VLM verification skipped (tools unavailable)")

    # Pass criteria: Minimum 3 files fixed AND VLM verification passed
    passed = (files_modified >= 3) and vlm_passed and (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }