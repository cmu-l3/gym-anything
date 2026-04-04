#!/bin/bash
# export_result.sh — security_hardening_service_account
echo "=== Exporting security_hardening_service_account result ==="

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

# ── svc-deploy user ───────────────────────────────────────────────────────────
user = art_get("/security/users/svc-deploy") or {}
user_found = isinstance(user, dict) and user.get("name", "").lower() == "svc-deploy"
result["svc_deploy_user"] = {
    "found": user_found,
    "admin": bool(user.get("admin", True)) if user_found else True,
    "email": user.get("email", "") if user_found else "",
    "groups": [g.lower() for g in (user.get("groups") or [])] if user_found else [],
}

# ── ci-services group ─────────────────────────────────────────────────────────
code = http_code("/security/groups/ci-services")
if code == "200":
    group = art_get("/security/groups/ci-services") or {}
    result["ci_services_group"] = {
        "found": True,
        "userNames": [u.lower() for u in (group.get("userNames") or [])],
    }
else:
    groups = art_get("/security/groups") or []
    names = [(g.get("name","") if isinstance(g,dict) else str(g)).lower() for g in groups]
    result["ci_services_group"] = {"found": "ci-services" in names, "userNames": []}

# ── npm-builds repo ───────────────────────────────────────────────────────────
repos = art_get("/repositories") or []
npm_builds = next(
    (r for r in repos if isinstance(r,dict) and r.get("key","").lower() == "npm-builds"),
    {}
)
result["npm_builds_repo"] = {
    "found": bool(npm_builds),
    "type": npm_builds.get("type", ""),
    "packageType": npm_builds.get("packageType", ""),
}

# ── svc-deploy-perms permission ───────────────────────────────────────────────
perm = art_get("/security/permissions/svc-deploy-perms") or {}
group_privs = {}
if perm.get("principals", {}) and "groups" in perm["principals"]:
    group_privs = perm["principals"]["groups"]
result["svc_deploy_perms"] = {
    "found": bool(perm.get("name") == "svc-deploy-perms"),
    "repositories": perm.get("repositories", []),
    "group_privs": group_privs,
}

# ── Access token ──────────────────────────────────────────────────────────────
tokens_data = access_get("/v1/tokens") or {}
token_found = False
for t in (tokens_data.get("tokens") or []):
    if "Q1 2026 rotation" in (t.get("description", "") or ""):
        token_found = True
        break
result["q1_rotation_token"] = {"found": token_found}

# ── Write ─────────────────────────────────────────────────────────────────────
with open("/tmp/security_hardening_service_account_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/security_hardening_service_account_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
