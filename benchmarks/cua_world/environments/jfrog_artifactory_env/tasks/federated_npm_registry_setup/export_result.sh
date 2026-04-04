#!/bin/bash
# export_result.sh — federated_npm_registry_setup
echo "=== Exporting federated_npm_registry_setup result ==="

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

result = {}

repos = art_get("/repositories") or []
repo_map = {r.get("key","").lower(): r for r in repos if isinstance(r, dict)}

# npm-internal
r = repo_map.get("npm-internal", {})
result["npm_internal"] = {
    "found": bool(r),
    "type": r.get("type",""),
    "packageType": r.get("packageType",""),
}

# npmjs-mirror — get detail for URL
r = repo_map.get("npmjs-mirror", {})
detail = art_get("/repositories/npmjs-mirror") or {}
result["npmjs_mirror"] = {
    "found": bool(r),
    "type": r.get("type",""),
    "packageType": r.get("packageType",""),
    "url": detail.get("url","") or detail.get("remoteUrl",""),
}

# npm-all — get detail for included repos
r = repo_map.get("npm-all", {})
detail2 = art_get("/repositories/npm-all") or {}
result["npm_all"] = {
    "found": bool(r),
    "type": r.get("type",""),
    "packageType": r.get("packageType",""),
    "repositories": detail2.get("repositories", []),
}

# frontend-lead user
user = art_get("/security/users/frontend-lead") or {}
user_found = isinstance(user, dict) and user.get("name","").lower() == "frontend-lead"
result["frontend_lead_user"] = {
    "found": user_found,
    "admin": bool(user.get("admin", True)) if user_found else True,
    "email": user.get("email","") if user_found else "",
    "groups": [g.lower() for g in (user.get("groups") or [])] if user_found else [],
}

# frontend-developers group
code = http_code("/security/groups/frontend-developers")
if code == "200":
    group = art_get("/security/groups/frontend-developers") or {}
    result["frontend_developers_group"] = {
        "found": True,
        "userNames": [u.lower() for u in (group.get("userNames") or [])],
    }
else:
    groups = art_get("/security/groups") or []
    names = [(g.get("name","") if isinstance(g,dict) else str(g)).lower() for g in groups]
    result["frontend_developers_group"] = {"found": "frontend-developers" in names, "userNames": []}

# frontend-npm-perms permission
perm = art_get("/security/permissions/frontend-npm-perms") or {}
group_privs = {}
if isinstance(perm.get("principals"), dict) and "groups" in perm["principals"]:
    group_privs = perm["principals"]["groups"]
result["frontend_npm_perms"] = {
    "found": bool(perm.get("name") == "frontend-npm-perms"),
    "repositories": perm.get("repositories", []),
    "group_privs": group_privs,
}

with open("/tmp/federated_npm_registry_setup_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/federated_npm_registry_setup_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
