#!/bin/bash
# export_result.sh — multi_team_pypi_infrastructure
echo "=== Exporting multi_team_pypi_infrastructure result ==="

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

def get_perm(name):
    perm = art_get(f"/security/permissions/{name}") or {}
    group_privs = {}
    if isinstance(perm.get("principals"), dict):
        group_privs = perm["principals"].get("groups", {})
    return {
        "found": bool(perm.get("name") == name),
        "repositories": perm.get("repositories", []),
        "group_privs": group_privs,
    }

result = {}

repos = art_get("/repositories") or []
repo_map = {r.get("key","").lower(): r for r in repos if isinstance(r, dict)}

for key in ("pypi-datascience", "pypi-mlops"):
    r = repo_map.get(key, {})
    slug = key.replace("-", "_")
    result[slug] = {"found": bool(r), "type": r.get("type",""), "packageType": r.get("packageType","")}

# pypi-org-proxy with URL
r = repo_map.get("pypi-org-proxy", {})
detail = art_get("/repositories/pypi-org-proxy") or {}
result["pypi_org_proxy"] = {
    "found": bool(r),
    "type": r.get("type",""),
    "packageType": r.get("packageType",""),
    "url": detail.get("url","") or detail.get("remoteUrl",""),
}

# pypi-all with included repos
r = repo_map.get("pypi-all", {})
detail2 = art_get("/repositories/pypi-all") or {}
result["pypi_all"] = {
    "found": bool(r),
    "type": r.get("type",""),
    "packageType": r.get("packageType",""),
    "repositories": detail2.get("repositories", []),
}

# Groups
for grp in ("data-scientists", "mlops-engineers"):
    slug = grp.replace("-","_")
    code = http_code(f"/security/groups/{grp}")
    if code == "200":
        result[f"{slug}_group"] = {"found": True}
    else:
        groups = art_get("/security/groups") or []
        names = [(g.get("name","") if isinstance(g,dict) else str(g)).lower() for g in groups]
        result[f"{slug}_group"] = {"found": grp in names}

# Permissions
result["ds_pypi_perms"] = get_perm("ds-pypi-perms")
result["mlops_pypi_perms"] = get_perm("mlops-pypi-perms")

with open("/tmp/multi_team_pypi_infrastructure_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/multi_team_pypi_infrastructure_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
