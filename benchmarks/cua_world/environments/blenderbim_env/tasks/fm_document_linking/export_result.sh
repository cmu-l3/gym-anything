#!/bin/bash
echo "=== Exporting fm_document_linking result ==="

source /workspace/scripts/task_utils.sh || true

# Take final screenshot before parsing result
take_screenshot /tmp/task_final_screenshot.png || true

RESULT_FILE="/tmp/fm_document_result.json"

# ── Write the export Python script ────────────────────────────────────────
cat > /tmp/export_fm_docs.py << 'PYEOF'
import sys
import json
import os

sys.path.insert(0, '/home/ga/.config/blender/4.2/extensions/user_default/bonsai/libs/site/packages')

ifc_path = "/home/ga/BIMProjects/fzk_fm_handover.ifc"

# Read task start timestamp
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
        "total_documents": 0,
        "document_names": [],
        "num_relationships": 0,
        "num_associated_elements": 0,
        "task_start": task_start
    }
else:
    try:
        import ifcopenshell
        ifc = ifcopenshell.open(ifc_path)
        
        # Count documents (accept both Information and Reference)
        doc_infos = list(ifc.by_type("IfcDocumentInformation"))
        doc_refs = list(ifc.by_type("IfcDocumentReference"))
        
        doc_names = []
        for d in doc_infos:
            if getattr(d, "Name", None):
                doc_names.append(d.Name)
        for d in doc_refs:
            name = getattr(d, "Name", None) or getattr(d, "Identification", None)
            if name:
                doc_names.append(name)
                
        total_documents = len(doc_infos) + len(doc_refs)
        
        # Count relationships
        rel_docs = list(ifc.by_type("IfcRelAssociatesDocument"))
        num_relationships = len(rel_docs)
        
        # Count uniquely associated elements
        associated_elements = set()
        for rel in rel_docs:
            for obj in (rel.RelatedObjects or []):
                associated_elements.add(obj.id())
                
        num_associated_elements = len(associated_elements)
        
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "total_documents": total_documents,
            "document_names": doc_names,
            "num_relationships": num_relationships,
            "num_associated_elements": num_associated_elements,
            "task_start": task_start
        }
    except Exception as e:
        result = {
            "file_exists": True,
            "file_mtime": os.path.getmtime(ifc_path),
            "total_documents": 0,
            "document_names": [],
            "num_relationships": 0,
            "num_associated_elements": 0,
            "task_start": task_start,
            "error": str(e)
        }

print("RESULT:" + json.dumps(result))
PYEOF

# ── Run via blender --background to access bundled ifcopenshell ────────────
/opt/blender/blender --background --python /tmp/export_fm_docs.py 2>&1 \
    | grep 'RESULT:' | sed 's/RESULT://' > "$RESULT_FILE"

# ── Fallback if export produced no output ─────────────────────────────────
if [ ! -s "$RESULT_FILE" ]; then
    echo '{"file_exists":false,"file_mtime":0,"total_documents":0,"num_relationships":0,"num_associated_elements":0,"task_start":0,"error":"Export script produced no output"}' > "$RESULT_FILE"
fi

echo "Export complete:"
cat "$RESULT_FILE"