#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Build Dependency Resolver Task ==="

WORKSPACE_DIR="/home/ga/workspace/buildsys"
sudo -u ga mkdir -p "$WORKSPACE_DIR/resolver"
sudo -u ga mkdir -p "$WORKSPACE_DIR/scheduler"
sudo -u ga mkdir -p "$WORKSPACE_DIR/packages"

# Create package manifests
python3 << 'PYMANIFEST'
import json, os
workspace = "/home/ga/workspace/buildsys"
pkgs = {
    "core": {"version": "1.0.0", "deps": []},
    "utils": {"version": "1.1.0", "deps": ["core"]},
    "logger": {"version": "2.0.0-alpha.1", "deps": ["core"]},
    "db-client": {"version": "1.5.2", "deps": ["core", "utils"]},
    "auth": {"version": "3.0.0", "deps": ["db-client", "logger"]},
    "api-server": {"version": "2.1.0", "deps": ["auth", "db-client", "logger"]},
    "cli": {"version": "1.0.0", "deps": ["api-server", "utils"]},
    "dashboard": {"version": "1.2.0", "deps": ["api-server"]},
    "metrics": {"version": "0.9.0", "deps": ["logger"]},
    "telemetry": {"version": "1.0.0", "deps": ["metrics", "core"]},
    "billing": {"version": "2.0.0", "deps": ["db-client", "metrics"]},
    "notifications": {"version": "1.1.0", "deps": ["core", "logger"]},
    "worker": {"version": "1.5.0", "deps": ["db-client", "notifications"]},
    "scheduler": {"version": "2.0.1", "deps": ["worker", "telemetry"]},
    "reports": {"version": "1.0.0", "deps": ["db-client", "billing"]},
    "admin-panel": {"version": "1.0.0", "deps": ["dashboard", "reports"]},
    "gateway": {"version": "2.0.0", "deps": ["api-server", "auth", "telemetry"]},
    "monorepo-tools": {"version": "1.0.0", "deps": ["cli"]}
}
for k, v in pkgs.items():
    with open(f"{workspace}/packages/{k}.json", "w") as f:
        json.dump({"name": k, "version": v["version"], "dependencies": {d: "*" for d in v["deps"]}}, f, indent=2)
PYMANIFEST

# Initialize Python modules
sudo -u ga touch "$WORKSPACE_DIR/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/resolver/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/scheduler/__init__.py"

# ──────────────────────────────────────────────────────────
# Bug 1: resolver/version.py (SemVer 2.0.0 violation)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/resolver/version.py" << 'EOF'
def compare_versions(v1, v2):
    """
    Compare two Semantic Versioning 2.0.0 strings.
    Returns 1 if v1 > v2, -1 if v1 < v2, 0 if equal.
    """
    def parse(v):
        if '-' in v:
            base, pre = v.split('-', 1)
            return [int(x) for x in base.split('.')], pre.split('.')
        return [int(x) for x in v.split('.')], []

    b1, p1 = parse(v1)
    b2, p2 = parse(v2)

    if b1 != b2:
        return 1 if b1 > b2 else -1

    # Bug: Ignores release > pre-release rule (e.g., 1.0.0 > 1.0.0-alpha)
    # Bug: Compares pre-release identifiers lexicographically (e.g., "12" < "9")
    if p1 != p2:
        return 1 if p1 > p2 else -1

    return 0
EOF

# ──────────────────────────────────────────────────────────
# Bug 2: resolver/dependency_graph.py (Cycle detection)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/resolver/dependency_graph.py" << 'EOF'
class DependencyGraph:
    def __init__(self):
        self.edges = {}

    def add_edge(self, node, dep):
        if node not in self.edges:
            self.edges[node] = []
        if dep not in self.edges[node]:
            self.edges[node].append(dep)

    def has_cycle(self):
        """Returns True if the dependency graph contains a cycle."""
        visited = set()
        
        def dfs(node):
            if node in visited:
                # Bug: Triggers on diamond dependencies (e.g. A->B->D, A->C->D)
                # because D is marked visited by B, then rejected when C visits it.
                return True
            
            visited.add(node)
            for dep in self.edges.get(node, []):
                if dfs(dep):
                    return True
            return False

        for n in self.edges:
            if dfs(n):
                return True
        return False
EOF

# ──────────────────────────────────────────────────────────
# Bug 3: resolver/constraint_solver.py (Bound inclusion)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/resolver/constraint_solver.py" << 'EOF'
from resolver.version import compare_versions

def satisfies(version, constraint):
    """Check if version satisfies the given range constraint."""
    if not constraint or constraint == "*":
        return True

    parts = constraint.split(',')
    for part in parts:
        op = ''.join([c for c in part if c in '<=>'])
        target = part[len(op):]

        comp = compare_versions(version, target)

        if op == '<=' and comp > 0:
            return False
        elif op == '<' and comp > 0:
            # Bug: Treats `<` as `<=`. If comp == 0, it doesn't return False!
            return False
        elif op == '>=' and comp < 0:
            return False
        elif op == '>' and comp <= 0:
            return False
        elif op == '==' and comp != 0:
            return False

    return True
EOF

# ──────────────────────────────────────────────────────────
# Bug 4: scheduler/topo_sort.py (Build ordering)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/scheduler/topo_sort.py" << 'EOF'
def get_build_order(graph):
    """
    Returns a valid build order (list of package names) such that 
    no package is built before its dependencies.
    """
    visited = set()
    order = []

    def dfs(node):
        if node in visited:
            return
        visited.add(node)
        for dep in graph.edges.get(node, []):
            dfs(dep)
        order.append(node)

    for n in graph.edges:
        dfs(n)

    # Bug: Reverses the correct DFS postfix order. 
    # Dependencies end up being built AFTER their dependents!
    return order[::-1]
EOF

# ──────────────────────────────────────────────────────────
# Bug 5: scheduler/cache_manager.py (Invalidation)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/scheduler/cache_manager.py" << 'EOF'
class CacheManager:
    def __init__(self, graph):
        self.cache = set()
        self.graph = graph

    def mark_built(self, package):
        self.cache.add(package)

    def is_cached(self, package):
        return package in self.cache

    def invalidate(self, package):
        """Invalidate cache for a package and all packages that depend on it."""
        if package in self.cache:
            self.cache.remove(package)
            
        # Bug: Does not traverse the graph to invalidate transitive dependents
        # Packages that depend on `package` retain stale artifacts.
EOF

# ──────────────────────────────────────────────────────────
# Test Suite (for the agent)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/test_build.py" << 'EOF'
import unittest
from resolver.version import compare_versions
from resolver.dependency_graph import DependencyGraph
from resolver.constraint_solver import satisfies
from scheduler.topo_sort import get_build_order
from scheduler.cache_manager import CacheManager

class TestBuildSystem(unittest.TestCase):
    def test_version_prerelease_numeric(self):
        # 1.0.0-alpha.12 should be > 1.0.0-alpha.9
        self.assertEqual(compare_versions("1.0.0-alpha.12", "1.0.0-alpha.9"), 1)

    def test_version_release_vs_prerelease(self):
        # 1.0.0 should be > 1.0.0-rc.1
        self.assertEqual(compare_versions("1.0.0", "1.0.0-rc.1"), 1)

    def test_cycle_diamond(self):
        g = DependencyGraph()
        g.add_edge("A", "B")
        g.add_edge("A", "C")
        g.add_edge("B", "D")
        g.add_edge("C", "D")
        self.assertFalse(g.has_cycle(), "Diamond dependency incorrectly flagged as cycle")

    def test_constraint_exclusive_upper(self):
        # <2.0.0 should NOT include 2.0.0
        self.assertFalse(satisfies("2.0.0", ">=1.0.0,<2.0.0"))

    def test_build_order(self):
        g = DependencyGraph()
        g.add_edge("app", "core")
        order = get_build_order(g)
        self.assertLess(order.index("core"), order.index("app"), "core must be built before app")

    def test_cache_transitive_invalidation(self):
        g = DependencyGraph()
        g.add_edge("app", "core")
        cm = CacheManager(g)
        cm.mark_built("core")
        cm.mark_built("app")
        cm.invalidate("core")
        self.assertFalse(cm.is_cached("app"), "app depends on core, should be invalidated")

if __name__ == "__main__":
    unittest.main()
EOF

chown -R ga:ga "$WORKSPACE_DIR"

# Focus VSCode
echo "Launching VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR"

# Wait for window and maximize
wait_for_window "Visual Studio Code" 30
WID=$(get_vscode_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_vscode_window
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="