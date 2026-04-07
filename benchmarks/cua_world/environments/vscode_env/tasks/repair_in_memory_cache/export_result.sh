#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

WORKSPACE_DIR="/home/ga/workspace/pycache"
RESULT_FILE="/tmp/task_result.json"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus VSCode and save files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Write a testing script to run inside the container and export results
cat > /tmp/run_hidden_tests.py << 'EOF'
import json
import sys
import os
import time

WORKSPACE = "/home/ga/workspace/pycache"
sys.path.insert(0, WORKSPACE)

results = {
    "lru": False,
    "ttl": False,
    "wal": False,
    "sharding": False,
    "sorted_set": False
}

# 1. Test LRU
try:
    from src.lru import LRUCache
    cache = LRUCache(2)
    cache.put("a", 1)
    cache.put("b", 2)
    cache.get("a")
    cache.put("c", 3)
    curr = cache.tail.prev
    backward_keys = []
    # Prevent infinite loop if pointers are severely mangled
    for _ in range(5):
        if curr == cache.head:
            break
        backward_keys.append(curr.key)
        curr = curr.prev
    if backward_keys == ["c", "a"]:
        results["lru"] = True
except Exception:
    pass

# 2. Test TTL
try:
    from src.ttl import TTLCache
    cache = TTLCache()
    cache.store["k1"] = "v1"
    cache.expires["k1"] = time.time() - 10
    cache.store["k2"] = "v2"
    cache.expires["k2"] = time.time() + 10
    cache.sweep()
    if "k1" not in cache.store and "k2" in cache.store:
        results["ttl"] = True
except Exception:
    pass

# 3. Test WAL
try:
    from src.wal import WriteAheadLog
    wal_file = "/tmp/test.wal"
    if os.path.exists(wal_file): os.remove(wal_file)
    wal = WriteAheadLog(wal_file)
    wal.log_expire("key1", 60)
    with open(wal_file) as f:
        content = f.read()
    if any(str(int(time.time()))[:5] in token for token in content.split()):
        results["wal"] = True
except Exception:
    pass

# 4. Test Sharding
try:
    from src.sharding import get_hash_tag
    if get_hash_tag("user:{123}:session:{abc}") == "123":
        results["sharding"] = True
except Exception:
    pass

# 5. Test Sorted Set
try:
    from src.sorted_set import SortedSet
    s = SortedSet()
    s.add("b", 10)
    s.add("a", 10)
    s.add("c", 5)
    if [x[1] for x in s.data] == ["c", "a", "b"]:
        results["sorted_set"] = True
except Exception:
    pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)
EOF

# Run the test evaluation
python3 /tmp/run_hidden_tests.py

# Add mtime/app metadata to the result json
python3 -c "
import json, os
with open('/tmp/task_result.json', 'r') as f:
    data = json.load(f)

workspace = '/home/ga/workspace/pycache/src'
mtimes = {}
for file in ['lru.py', 'ttl.py', 'wal.py', 'sharding.py', 'sorted_set.py']:
    try:
        mtimes[file] = os.path.getmtime(os.path.join(workspace, file))
    except Exception:
        mtimes[file] = 0

data['mtimes'] = mtimes
data['vscode_running'] = os.system('pgrep -f code > /dev/null') == 0

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

chmod 666 "$RESULT_FILE"
echo "=== Export Complete ==="
cat "$RESULT_FILE"