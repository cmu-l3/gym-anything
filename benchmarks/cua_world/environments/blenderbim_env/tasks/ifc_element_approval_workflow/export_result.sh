#!/bin/bash
echo "=== Exporting ifc_element_approval_workflow result ==="

source /workspace/scripts/task_utils.sh || true

take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/approval_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_approvals.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_element_approvals.ifc"

task_start = 0.0
try:
    with open("/tmp/task_start_timestamp") as f:
        task_start = float(f.read().strip())
except Exception:
    pass

if not os.path.exists(ifc_path):
    result = {
        "file_exists": False,
        "file_mtime": 0.0,
        "n_approvals": 0,
        "statuses": [],
        "approved_slabs": 0,
        "pending_rejected_windows": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # 1. Inspect IfcApproval entities
        approvals = list(ifc.by_type("IfcApproval"))
        statuses = []
        for a in approvals:
            status = a.Status if a.Status else ""
            if status:
                statuses.append(status.upper())
                
        # 2. Inspect assignments via IfcRelAssociatesApproval
        rels = list(ifc.by_type("IfcRelAssociatesApproval"))
        approved_slab_ids = set()
        pending_window_ids = set()
        
        for rel in rels:
            approval = rel.RelatingApproval
            if not approval:
                continue
                
            status = (approval.Status or "").upper()
            related_objects = rel.RelatedObjects or []
            
            if "APPROVED" in status:
                for obj in related_objects:
                    if obj.is_a("IfcSlab"):
                        approved_slab_ids.add(obj.id())
                        
            if "PENDING" in status or "REJECTED" in status:
                for obj in related_objects:
                    if obj.is_a("IfcWindow"):
                        pending_window_ids.add(obj.id())

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_approvals": len(approvals),
            "statuses": statuses,
            "approved_slabs": len(approved_slab_ids),
            "pending_rejected_windows": len(pending_window_ids),
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_approvals": 0,
            "statuses": [],
            "approved_slabs": 0,
            "pending_rejected_windows": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_approvals.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"n_approvals":0,"statuses":[],"approved_slabs":0,"pending_rejected_windows":0,"task_start":0,"error":"Export script failed"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"