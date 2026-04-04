#!/bin/bash
# export_result.sh — tradex_platform_setup
echo "=== Exporting tradex_platform_setup result ==="

source /workspace/scripts/task_utils.sh

python3 << 'PYEOF'
import json, subprocess

URL  = "http://localhost:8082"
AUTH = ("admin", "password")

def art_get(path):
    try:
        r = subprocess.run(
            ["curl", "-s", "-u", f"{AUTH[0]}:{AUTH[1]}",
             f"{URL}/artifactory/api{path}"],
            capture_output=True, text=True, timeout=15
        )
        return json.loads(r.stdout)
    except Exception:
        return None

def access_get(path):
    try:
        r = subprocess.run(
            ["curl", "-s", "-u", f"{AUTH[0]}:{AUTH[1]}",
             f"{URL}/access/api{path}"],
            capture_output=True, text=True, timeout=15
        )
        return json.loads(r.stdout)
    except Exception:
        return None

def http_code(path):
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

repos = art_get("/repositories") or []
repo_map = {r.get("key","").lower(): r for r in repos if isinstance(r, dict)}

# tradex-artifacts (Generic local)
r = repo_map.get("tradex-artifacts", {})
result["tradex_artifacts"] = {
    "found": bool(r),
    "type": r.get("type",""),
    "packageType": r.get("packageType",""),
}

# tradex-maven-releases (Maven local)
r = repo_map.get("tradex-maven-releases", {})
result["tradex_maven_releases"] = {
    "found": bool(r),
    "type": r.get("type",""),
    "packageType": r.get("packageType",""),
}

# tradex-developers group
code = http_code("/security/groups/tradex-developers")
if code == "200":
    result["tradex_developers_group"] = {"found": True}
else:
    groups = art_get("/security/groups") or []
    names = [(g.get("name","") if isinstance(g,dict) else str(g)).lower() for g in groups]
    result["tradex_developers_group"] = {"found": "tradex-developers" in names}

# tradex-dev-perms permission
perm = art_get("/security/permissions/tradex-dev-perms") or {}
group_privs = {}
if isinstance(perm.get("principals"), dict):
    group_privs = perm["principals"].get("groups", {})
result["tradex_dev_perms"] = {
    "found": bool(perm.get("name") == "tradex-dev-perms"),
    "repositories": perm.get("repositories", []),
    "group_privs": group_privs,
}

# Access token "TradeX CI/CD production token"
tokens_data = access_get("/v1/tokens") or {}
token_found = False
for t in (tokens_data.get("tokens") or []):
    if "TradeX CI/CD production token" in (t.get("description","") or ""):
        token_found = True
        break
result["tradex_cicd_token"] = {"found": token_found}

# commons-io artifact in tradex-artifacts
search = art_get(
    "/search/quick?name=commons-io-2.15.1.jar&repos=tradex-artifacts"
) or {}
results_list = search.get("results", [])
if not results_list:
    search2 = art_get(
        "/search/quick?name=commons-io*.jar&repos=tradex-artifacts"
    ) or {}
    results_list = search2.get("results", [])
result["commons_io_artifact"] = {
    "found": len(results_list) > 0,
    "count": len(results_list),
}

with open("/tmp/tradex_platform_setup_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/tradex_platform_setup_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
