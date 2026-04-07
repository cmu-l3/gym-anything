#!/bin/bash
echo "=== Exporting prefabricated_assembly_modeling result ==="

source /workspace/scripts/task_utils.sh || true
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/prefab_result.json"

cat > /tmp/export_prefab.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/prefab_bathroom_pod.ifc"

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
        "n_assemblies": 0,
        "n_walls": 0,
        "n_slabs": 0,
        "n_terminals": 0,
        "aggregated_walls": 0,
        "aggregated_slabs": 0,
        "aggregated_terminals": 0,
        "assembly_is_contained": False,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)

        # 1. Gather all required elements
        assemblies = list(ifc.by_type("IfcElementAssembly"))
        walls = list(ifc.by_type("IfcWall"))
        slabs = list(ifc.by_type("IfcSlab"))
        terminals = list(ifc.by_type("IfcSanitaryTerminal"))

        # 2. Check Aggregation (IfcRelAggregates)
        # We look for any assembly that acts as a RelatingObject and collects its RelatedObjects
        aggregated_ids = set()
        for rel in ifc.by_type("IfcRelAggregates"):
            rel_obj = rel.RelatingObject
            if rel_obj and rel_obj.is_a("IfcElementAssembly"):
                for obj in (rel.RelatedObjects or []):
                    aggregated_ids.add(obj.id())
        
        # Also check IfcRelNests as Bonsai sometimes uses this for assemblies depending on settings
        for rel in ifc.by_type("IfcRelNests"):
            rel_obj = rel.RelatingObject
            if rel_obj and rel_obj.is_a("IfcElementAssembly"):
                for obj in (rel.RelatedObjects or []):
                    aggregated_ids.add(obj.id())

        # Count how many of our specific components are successfully aggregated into an assembly
        agg_walls = sum(1 for w in walls if w.id() in aggregated_ids)
        agg_slabs = sum(1 for s in slabs if s.id() in aggregated_ids)
        agg_terminals = sum(1 for t in terminals if t.id() in aggregated_ids)

        # 3. Check Spatial Containment (IfcRelContainedInSpatialStructure)
        assembly_contained = False
        for rel in ifc.by_type("IfcRelContainedInSpatialStructure"):
            for obj in (rel.RelatedElements or []):
                if obj.is_a("IfcElementAssembly"):
                    assembly_contained = True
                    break
            if assembly_contained:
                break

        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_assemblies": len(assemblies),
            "n_walls": len(walls),
            "n_slabs": len(slabs),
            "n_terminals": len(terminals),
            "aggregated_walls": agg_walls,
            "aggregated_slabs": agg_slabs,
            "aggregated_terminals": agg_terminals,
            "assembly_is_contained": assembly_contained,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "n_assemblies": 0,
            "n_walls": 0,
            "n_slabs": 0,
            "n_terminals": 0,
            "aggregated_walls": 0,
            "aggregated_slabs": 0,
            "aggregated_terminals": 0,
            "assembly_is_contained": False,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

/opt/blender/blender --background --python /tmp/export_prefab.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"task_start":0,"error":"No output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"