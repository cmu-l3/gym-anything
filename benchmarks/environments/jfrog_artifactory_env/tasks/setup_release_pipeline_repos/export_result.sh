#!/bin/bash
# export_result.sh — setup_release_pipeline_repos
# Queries Artifactory REST API and writes verification JSON to
# /tmp/setup_release_pipeline_repos_result.json for the verifier to read.
echo "=== Exporting setup_release_pipeline_repos result ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/setup_release_pipeline_repos_result.json"

python3 << 'PYEOF'
import json, subprocess, sys

URL  = "http://localhost:8082"
AUTH = ("admin", "password")

def art_get(path):
    """GET /artifactory/api{path} — returns parsed JSON or None."""
    try:
        r = subprocess.run(
            ["curl", "-s", "-u", f"{AUTH[0]}:{AUTH[1]}",
             f"{URL}/artifactory/api{path}"],
            capture_output=True, text=True, timeout=15
        )
        return json.loads(r.stdout)
    except Exception:
        return None

def http_code(path):
    """Return HTTP status code as string for /artifactory/api{path}."""
    try:
        r = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
             "-u", f"{AUTH[0]}:{AUTH[1]}",
             f"{URL}/artifactory/api{path}"],
            capture_output=True, text=True, timeout=10
        )
        return r.stdout.strip()
    except Exception:
        return "000"

result = {}

# ── Repo list ──────────────────────────────────────────────────────────────────
repos = art_get("/repositories") or []
repo_map = {r.get("key","").lower(): r for r in repos if isinstance(r, dict)}

# ms-releases
r = repo_map.get("ms-releases", {})
result["ms_releases"] = {
    "found": bool(r),
    "type": r.get("type", ""),
    "packageType": r.get("packageType", ""),
}

# maven-central-proxy — also fetch individual detail for URL
r = repo_map.get("maven-central-proxy", {})
detail = art_get("/repositories/maven-central-proxy") or {}
result["maven_central_proxy"] = {
    "found": bool(r),
    "type": r.get("type", ""),
    "packageType": r.get("packageType", ""),
    "url": detail.get("url", "") or detail.get("remoteUrl", ""),
}

# ms-build-virtual — also fetch individual detail for included repos
r = repo_map.get("ms-build-virtual", {})
detail2 = art_get("/repositories/ms-build-virtual") or {}
result["ms_build_virtual"] = {
    "found": bool(r),
    "type": r.get("type", ""),
    "packageType": r.get("packageType", ""),
    "repositories": detail2.get("repositories", []),
}

# ── Group ──────────────────────────────────────────────────────────────────────
code = http_code("/security/groups/build-engineers")
if code == "200":
    result["build_engineers_group"] = {"found": True}
else:
    groups = art_get("/security/groups") or []
    names = [(g.get("name","") if isinstance(g,dict) else str(g)).lower() for g in groups]
    result["build_engineers_group"] = {"found": "build-engineers" in names}

# ── Permission ─────────────────────────────────────────────────────────────────
perm = art_get("/security/permissions/build-access") or {}
group_privs = {}
principals = perm.get("principals", {}) or {}
if "groups" in principals:
    group_privs = principals["groups"]
result["build_access_permission"] = {
    "found": bool(perm.get("name") == "build-access"),
    "repositories": perm.get("repositories", []),
    "group_privs": group_privs,
}

# ── Write result ───────────────────────────────────────────────────────────────
with open("/tmp/setup_release_pipeline_repos_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/setup_release_pipeline_repos_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
