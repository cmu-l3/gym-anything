#!/usr/bin/env python3
"""
Setup realistic quality data for odoo_quality_env.

Creates:
- Products (if not present from demo data)
- Quality Control Points (for tasks that modify existing QCPs)
- Quality Alerts (for tasks that operate on pre-existing alerts)
- Quality Checks (for pass/fail tasks)

Uses Odoo XML-RPC to ensure data is correctly linked in the database.
"""

import xmlrpc.client
import sys
import time
import json

ODOO_URL = "http://localhost:8069"
ODOO_DB = "odoo_quality"
ODOO_USER = "admin"
ODOO_PASSWORD = "admin"

MAX_RETRIES = 10
RETRY_DELAY = 15


def connect():
    """Connect to Odoo via XML-RPC with retries."""
    for attempt in range(MAX_RETRIES):
        try:
            common = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/common")
            uid = common.authenticate(ODOO_DB, ODOO_USER, ODOO_PASSWORD, {})
            if uid:
                models = xmlrpc.client.ServerProxy(f"{ODOO_URL}/xmlrpc/2/object")
                print(f"Connected to Odoo as uid={uid}")
                return uid, models
            print(f"Authentication failed (attempt {attempt+1}), retrying...")
        except Exception as e:
            print(f"Connection error (attempt {attempt+1}): {e}", file=sys.stderr)
        time.sleep(RETRY_DELAY)
    print("ERROR: Could not connect to Odoo after retries", file=sys.stderr)
    sys.exit(1)


def search_read(models, uid, model, domain, fields, limit=100):
    return models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, model, "search_read",
        [domain], {"fields": fields, "limit": limit}
    )


def search(models, uid, model, domain):
    return models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, model, "search", [domain]
    )


def create(models, uid, model, vals):
    return models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, model, "create", [vals]
    )


def write(models, uid, model, ids, vals):
    return models.execute_kw(
        ODOO_DB, uid, ODOO_PASSWORD, model, "write", [ids, vals]
    )


def get_or_create_product(models, uid, name, product_type="product"):
    """Get existing product or create it."""
    # Search by name (Odoo 17 uses JSONB for name)
    ids = search(models, uid, "product.template", [["name", "ilike", name]])
    if ids:
        records = search_read(models, uid, "product.template", [["id", "in", ids]],
                               ["id", "name"])
        # Find exact match
        for r in records:
            r_name = r["name"]
            if isinstance(r_name, dict):
                r_name = r_name.get("en_US", str(r_name))
            if r_name.strip().lower() == name.strip().lower():
                print(f"Found existing product: {name} (id={r['id']})")
                return r["id"]
    # Create product
    prod_id = create(models, uid, "product.template", {
        "name": name,
        "type": product_type,
        "sale_ok": True,
        "purchase_ok": True,
    })
    print(f"Created product: {name} (id={prod_id})")
    return prod_id


def get_product_variant_id(models, uid, template_id):
    """Get the product.product ID for a template."""
    ids = search(models, uid, "product.product", [["product_tmpl_id", "=", template_id]])
    return ids[0] if ids else None


def get_picking_type_id(models, uid, operation_type="incoming"):
    """Get stock.picking.type ID for a given type (incoming=Receipts)."""
    ids = search(models, uid, "stock.picking.type", [["code", "=", operation_type]])
    if ids:
        return ids[0]
    # Fallback: get any picking type
    ids = search(models, uid, "stock.picking.type", [])
    return ids[0] if ids else None


def get_quality_team_id(models, uid, name="Quality"):
    """Get or create a quality alert team."""
    ids = search(models, uid, "quality.alert.team", [["name", "ilike", name]])
    if ids:
        return ids[0]
    team_id = create(models, uid, "quality.alert.team", {"name": "Quality Control Team"})
    print(f"Created quality team: Quality Control Team (id={team_id})")
    return team_id


def get_alert_stage(models, uid, name_pattern):
    """Get alert stage ID by name pattern."""
    ids = search(models, uid, "quality.alert.stage", [["name", "ilike", name_pattern]])
    if ids:
        records = search_read(models, uid, "quality.alert.stage", [["id", "in", ids]], ["id", "name"])
        print(f"Found stages matching '{name_pattern}': {[r['name'] for r in records]}")
        return ids[0]
    return None


def get_test_type(models, uid):
    """Get quality check test types. Returns dict of type_name->id or values."""
    # In Odoo 17, quality.point may have 'test_type' as selection field
    # or test_type_id as many2one to quality.check.type
    try:
        # Try to get fields info to understand test_type field type
        fields_info = models.execute_kw(
            ODOO_DB, uid, ODOO_PASSWORD, "quality.point", "fields_get",
            [["test_type"]], {"attributes": ["type", "selection"]}
        )
        if "test_type" in fields_info:
            field = fields_info["test_type"]
            if field.get("type") == "selection":
                # Selection field - use string values directly
                vals = {k: k for k, v in field.get("selection", [])}
                print(f"test_type is selection field: {vals}")
                return vals
    except Exception as e:
        print(f"Warning: Could not introspect test_type field: {e}", file=sys.stderr)

    # Try quality.check.type model for many2one approach
    try:
        types = search_read(models, uid, "quality.check.type", [], ["id", "name", "technical_name"])
        if types:
            result = {}
            for t in types:
                tech_name = t.get("technical_name") or t.get("name", "").lower().replace(" ", "_")
                result[tech_name] = t["id"]
            print(f"Found quality check types: {list(result.keys())}")
            return result
    except Exception:
        pass

    # Fallback: return None (will skip test_type setting)
    return {}


def delete_if_exists(models, uid, model, domain):
    """Delete records matching domain."""
    ids = search(models, uid, model, domain)
    if ids:
        models.execute_kw(ODOO_DB, uid, ODOO_PASSWORD, model, "unlink", [ids])
        print(f"Deleted {len(ids)} existing {model} records")


def main():
    print("=== Setting up Odoo Quality data ===")

    uid, models = connect()

    # -----------------------------------------------------------
    # Get/create products
    # Using Odoo's official demo product names as base data
    # -----------------------------------------------------------
    print("\n--- Setting up products ---")
    cabinet_tmpl_id = get_or_create_product(models, uid, "Cabinet with Doors")
    screen_tmpl_id = get_or_create_product(models, uid, "Acoustic Bloc Screens")
    desk_tmpl_id = get_or_create_product(models, uid, "Customizable Desk")
    chair_tmpl_id = get_or_create_product(models, uid, "Office Chair")
    shelf_tmpl_id = get_or_create_product(models, uid, "Large Cabinet")

    cabinet_product_id = get_product_variant_id(models, uid, cabinet_tmpl_id)
    screen_product_id = get_product_variant_id(models, uid, screen_tmpl_id)
    desk_product_id = get_product_variant_id(models, uid, desk_tmpl_id)
    chair_product_id = get_product_variant_id(models, uid, chair_tmpl_id)
    shelf_product_id = get_product_variant_id(models, uid, shelf_tmpl_id)
    print(f"Cabinet with Doors: template={cabinet_tmpl_id}, variant={cabinet_product_id}")
    print(f"Acoustic Bloc Screens: template={screen_tmpl_id}, variant={screen_product_id}")
    print(f"Customizable Desk: template={desk_tmpl_id}, variant={desk_product_id}")
    print(f"Office Chair: template={chair_tmpl_id}, variant={chair_product_id}")
    print(f"Large Cabinet: template={shelf_tmpl_id}, variant={shelf_product_id}")

    # -----------------------------------------------------------
    # Get operation type for Receipts
    # -----------------------------------------------------------
    receipts_id = get_picking_type_id(models, uid, "incoming")
    print(f"\nReceipts operation type id={receipts_id}")

    # -----------------------------------------------------------
    # Get or create quality team
    # -----------------------------------------------------------
    team_id = get_quality_team_id(models, uid)
    print(f"Quality team id={team_id}")

    # -----------------------------------------------------------
    # Get alert stages (New / In Progress / Done)
    # -----------------------------------------------------------
    print("\n--- Getting alert stages ---")
    all_stages = search_read(models, uid, "quality.alert.stage", [], ["id", "name"])
    print(f"Available alert stages: {[(s['id'], s['name']) for s in all_stages]}")

    new_stage_id = None
    done_stage_id = None
    for s in all_stages:
        name_lower = s["name"].lower()
        if "new" in name_lower or "open" in name_lower:
            new_stage_id = s["id"]
        if "done" in name_lower or "close" in name_lower or "fold" in name_lower:
            done_stage_id = s["id"]

    # If no "Done" stage found, get the last stage
    if not done_stage_id and all_stages:
        # Sort by id descending and take the last
        done_stage_id = all_stages[-1]["id"]
    if not new_stage_id and all_stages:
        new_stage_id = all_stages[0]["id"]

    print(f"Using New stage id={new_stage_id}, Done stage id={done_stage_id}")

    # -----------------------------------------------------------
    # Get test types for quality control points
    # -----------------------------------------------------------
    print("\n--- Getting test types ---")
    test_types = get_test_type(models, uid)

    # -----------------------------------------------------------
    # Create Quality Control Points (5 QCPs across different operations)
    # -----------------------------------------------------------
    print("\n--- Creating Quality Control Points ---")

    def make_qcp(name, note, product_id, test_type_key="instructions"):
        delete_if_exists(models, uid, "quality.point", [["name", "=", name]])
        data = {
            "name": name,
            "note": note,
        }
        if product_id:
            data["product_ids"] = [(6, 0, [product_id])]
        if receipts_id:
            data["picking_type_ids"] = [(6, 0, [receipts_id])]
        if test_types:
            tv = test_types.get(test_type_key) or list(test_types.values())[0]
            if isinstance(tv, int):
                data["test_type_id"] = tv
            else:
                data["test_type"] = tv
        return create(models, uid, "quality.point", data)

    # QCP 1 — task: set_control_point_failure_message
    qcp_id = make_qcp(
        "Incoming Parts Verification",
        "Verify all incoming cabinet parts meet dimensional and finish specifications.",
        cabinet_product_id, "instructions"
    )
    print(f"Created QCP 'Incoming Parts Verification' id={qcp_id}")

    # QCP 2
    make_qcp(
        "Final Assembly Audit",
        "Audit final assembly for completeness and workmanship per ISO 9001 checklist.",
        cabinet_product_id, "passfail"
    )
    print("Created QCP 'Final Assembly Audit'")

    # QCP 3
    make_qcp(
        "Screen Dimensional Inspection",
        "Measure screen width and height against ±0.5 cm tolerance spec.",
        screen_product_id, "measure"
    )
    print("Created QCP 'Screen Dimensional Inspection'")

    # QCP 4 — task: create_quality_control_point target area
    make_qcp(
        "Desk Surface Flatness Check",
        "Verify desk surface flatness using reference straight-edge tool.",
        desk_product_id, "instructions"
    )
    print("Created QCP 'Desk Surface Flatness Check'")

    # QCP 5
    make_qcp(
        "Chair Stability Load Test",
        "Apply 150 kg static load for 5 minutes; no deformation or creak permitted.",
        chair_product_id, "passfail"
    )
    print("Created QCP 'Chair Stability Load Test'")

    # -----------------------------------------------------------
    # Create Quality Alerts — 18 alerts distributed across stages
    # ~8 in New, ~5 in In Progress, ~5 in Done
    # 4 are task-specific (named records tasks will operate on)
    # 14 are context/background records filling out the board
    # -----------------------------------------------------------
    print("\n--- Creating Quality Alerts ---")

    # Determine In Progress stage id
    in_progress_stage_id = None
    for s in all_stages:
        if "progress" in s["name"].lower() or "in progress" in s["name"].lower():
            in_progress_stage_id = s["id"]
    if not in_progress_stage_id:
        # fallback: middle stage
        if len(all_stages) >= 3:
            in_progress_stage_id = all_stages[1]["id"]
        else:
            in_progress_stage_id = new_stage_id

    def make_alert(name, description, priority, stage_id, product_id,
                   corrective_action="", preventive_action=""):
        delete_if_exists(models, uid, "quality.alert", [["name", "=", name]])
        data = {
            "name": name,
            "description": description,
            "priority": priority,
            "corrective_action": corrective_action,
            "preventive_action": preventive_action,
        }
        if product_id:
            data["product_id"] = product_id
        if stage_id:
            data["stage_id"] = stage_id
        return create(models, uid, "quality.alert", data)

    # ---- TASK-SPECIFIC ALERTS (New stage) ----

    # Alert for task: close_quality_alert (move this to Done)
    alert1_id = make_alert(
        "Paint Discoloration on Metal Panels",
        "Multiple units show discoloration and uneven paint coverage on metal panel surfaces. Affected batch: BATCH-2024-003.",
        "0", new_stage_id, cabinet_product_id
    )
    print(f"Created alert 'Paint Discoloration on Metal Panels' id={alert1_id}")

    # Alert for task: add_corrective_action (corrective_action field is empty)
    alert2_id = make_alert(
        "Incorrect Spacing Between Components",
        "Assembly inspection found spacing between components 3 mm larger than specification. Affects product stability. Batch: BATCH-2024-007.",
        "0", new_stage_id, cabinet_product_id
    )
    print(f"Created alert 'Incorrect Spacing Between Components' id={alert2_id}")

    # Alert for task: add_preventive_action (preventive_action field is empty)
    alert3_id = make_alert(
        "Material Hardness Below Specification",
        "Material hardness testing shows values 12% below minimum specification threshold. Supplier batch affected: Lot A-2024-112.",
        "1", new_stage_id, screen_product_id,
        corrective_action="Affected batch quarantined and supplier notified.",
        preventive_action=""
    )
    print(f"Created alert 'Material Hardness Below Specification' id={alert3_id}")

    # Alert for task: set_alert_priority (currently Normal, task sets to High)
    alert4_id = make_alert(
        "Critical Weld Failure on Frame",
        "Weld joint on main frame found to have micro-cracks. Structural integrity compromised. Immediate inspection of all units from same production run required.",
        "0", new_stage_id, cabinet_product_id
    )
    print(f"Created alert 'Critical Weld Failure on Frame' id={alert4_id}")

    # ---- BACKGROUND ALERTS — New stage ----
    make_alert(
        "Loose Hardware on Shelf Unit",
        "Customer return shows hardware (hinges, screws) insufficiently torqued on Lot SH-2024-021. 3 of 15 sampled units affected.",
        "0", new_stage_id, shelf_product_id
    )
    make_alert(
        "Desk Laminate Delamination",
        "Laminate surface peeling at corner joints after 48h humidity test. Affects desk units from supplier batch DK-2024-055.",
        "0", new_stage_id, desk_product_id
    )
    make_alert(
        "Chair Armrest Cracking",
        "Hairline cracks found on chair armrest injection moulding during 500-cycle fatigue test. Batch: CH-2024-009.",
        "1", new_stage_id, chair_product_id
    )
    make_alert(
        "Screen Frame Scratch on Delivery",
        "12 of 80 screens from delivery DL-2024-441 show scratches on aluminium frame. Transit packaging under review.",
        "0", new_stage_id, screen_product_id
    )
    print("Created 4 background New-stage alerts")

    # ---- BACKGROUND ALERTS — In Progress stage ----
    make_alert(
        "Cabinet Door Hinge Misalignment",
        "Door hinges misaligned by >2mm on 8 units from BATCH-2024-001. Investigation ongoing with production line supervisor.",
        "1", in_progress_stage_id, cabinet_product_id,
        corrective_action="Returned 8 units to assembly for hinge re-fitting. Production line tooling jig recalibration scheduled.",
    )
    make_alert(
        "Acoustic Panel Bonding Failure",
        "Acoustic bonding agent failed adhesion test at 60°C. Root cause analysis in progress with supplier Adhesive Corp.",
        "1", in_progress_stage_id, screen_product_id,
        corrective_action="Quarantined batch SP-2024-033. Awaiting alternative adhesive approval from engineering.",
    )
    make_alert(
        "Desk Height Adjustment Mechanism Stiff",
        "Height adjustment lever requires >25 N force, spec is <15 N. Supplier rework agreement in negotiation.",
        "0", in_progress_stage_id, desk_product_id,
        corrective_action="Issued NCR to supplier. 50 units on hold pending mechanical rework approval.",
    )
    make_alert(
        "Chair Foam Density Below Grade",
        "Foam density measured at 38 kg/m³; specification requires 42 kg/m³. Supplier substitution investigation active.",
        "1", in_progress_stage_id, chair_product_id,
        corrective_action="Batch CH-2024-004 quarantined. Alternative foam supplier being evaluated.",
    )
    make_alert(
        "Cabinet Coating Thickness Non-Uniform",
        "DFT gauge readings show 20–45 µm variance across cabinet surfaces; spec is 35±5 µm. Spray parameter audit underway.",
        "0", in_progress_stage_id, cabinet_product_id,
        corrective_action="Spray booth calibration performed. Re-testing 20 sample units before clearance.",
    )
    print("Created 5 background In-Progress alerts")

    # ---- BACKGROUND ALERTS — Done stage ----
    make_alert(
        "Screen Backlight Flicker at Low Brightness",
        "Flicker observed on PWM dimming below 20% brightness. Root cause: controller firmware bug. Resolved in FW v2.3.1.",
        "0", done_stage_id, screen_product_id,
        corrective_action="Firmware update deployed to all units. 100% test pass rate achieved.",
        preventive_action="Added firmware version check to incoming inspection protocol.",
    )
    make_alert(
        "Desk Leg Length Variation",
        "Leg length variation ±3 mm across batch causing table rock on flat surfaces. Resolved by supplier retooling.",
        "0", done_stage_id, desk_product_id,
        corrective_action="Supplier retooled CNC cutting program. Verified with CMM measurements.",
        preventive_action="Added in-process CNC measurement check every 50 units.",
    )
    make_alert(
        "Packaging Insufficient for Cabinet Weight",
        "Internal cardboard insufficient for 45 kg cabinet; 6 units damaged in transit. New packaging specification approved.",
        "0", done_stage_id, cabinet_product_id,
        corrective_action="Replaced single-wall with double-wall corrugated for all cabinet shipments.",
        preventive_action="Packaging design review added to new product introduction checklist.",
    )
    make_alert(
        "Chair Seat Fabric Pilling",
        "Customer complaints: fabric shows pilling after 3 months of normal use. Supplier provided higher Martindale-rated fabric.",
        "0", done_stage_id, chair_product_id,
        corrective_action="Fabric supplier changed to Testrite Grade B (30,000 Martindale cycles).",
        preventive_action="Updated fabric specification in supplier quality manual.",
    )
    make_alert(
        "Cabinet Lock Mechanism Sticky",
        "Lock cylinder requires excessive force to operate in cold temperatures. Resolved with food-grade lubricant in factory.",
        "0", done_stage_id, cabinet_product_id,
        corrective_action="Applied approved food-grade lubricant at assembly. All locks tested pre-shipment.",
        preventive_action="Added cold-temperature lock test to final QC inspection.",
    )
    print("Created 5 background Done-stage alerts")

    # -----------------------------------------------------------
    # Create Quality Checks — 6 checks in various states
    # 2 task-specific (none state), 4 background (pass/fail/none)
    # -----------------------------------------------------------
    print("\n--- Creating Quality Checks ---")

    def make_check(name, product_id, state, notes="", point_id=None):
        delete_if_exists(models, uid, "quality.check", [["name", "=", name]])
        data = {
            "name": name,
            "quality_state": state,
            "note": notes,
        }
        if product_id:
            data["product_id"] = product_id
        if point_id:
            data["point_id"] = point_id
        try:
            cid = create(models, uid, "quality.check", data)
            print(f"Created check '{name}' id={cid} state={state}")
            return cid
        except Exception as e:
            data.pop("point_id", None)
            try:
                cid = create(models, uid, "quality.check", data)
                print(f"Created check '{name}' id={cid} state={state} (no QCP)")
                return cid
            except Exception as e2:
                print(f"Warning: Could not create check '{name}': {e2}", file=sys.stderr)
                return None

    # Task-specific checks (both in 'none' state — tasks will pass/fail them)
    check1_id = make_check("Visual Inspection - Cabinet Finish", cabinet_product_id,
                            "none", point_id=qcp_id)
    check2_id = make_check("Dimension Verification - Screen Width", screen_product_id, "none")

    # Background checks in various states (fill out the list)
    make_check("Desk Surface Hardness Test", desk_product_id, "pass",
               "Brinell hardness 245 HB. Within 240–260 HB specification. PASS.")
    make_check("Chair Foam Compression Test", chair_product_id, "fail",
               "Compression set 42% after 22h at 70°C. Spec: <35%. Reject batch CH-2024-011.")
    make_check("Cabinet Lock Torque Check", cabinet_product_id, "pass",
               "Lock torque 1.2 Nm. Within 0.8–1.5 Nm spec. All 5 sampled units passed.")
    make_check("Screen Colour Uniformity Audit", screen_product_id, "none")

    # -----------------------------------------------------------
    # Save task configuration summary
    # -----------------------------------------------------------
    config = {
        "products": {
            "cabinet_tmpl_id": cabinet_tmpl_id,
            "cabinet_product_id": cabinet_product_id,
            "screen_tmpl_id": screen_tmpl_id,
            "screen_product_id": screen_product_id,
            "desk_product_id": desk_product_id,
            "chair_product_id": chair_product_id,
            "shelf_product_id": shelf_product_id,
        },
        "alerts": {
            "close_quality_alert": {"name": "Paint Discoloration on Metal Panels", "id": alert1_id},
            "add_corrective_action": {"name": "Incorrect Spacing Between Components", "id": alert2_id},
            "add_preventive_action": {"name": "Material Hardness Below Specification", "id": alert3_id},
            "set_alert_priority": {"name": "Critical Weld Failure on Frame", "id": alert4_id},
        },
        "qcps": {
            "set_control_point_failure_message": {"name": "Incoming Parts Verification", "id": qcp_id},
        },
        "done_stage_id": done_stage_id,
        "new_stage_id": new_stage_id,
        "in_progress_stage_id": in_progress_stage_id,
    }

    with open("/tmp/odoo_quality_config.json", "w") as f:
        json.dump(config, f, indent=2)

    print("\n=== Quality data setup complete ===")
    print("Configuration saved to /tmp/odoo_quality_config.json")
    print(f"\nData summary:")
    print(f"  Products: 5 (Cabinet with Doors, Acoustic Bloc Screens, Customizable Desk, Office Chair, Large Cabinet)")
    print(f"  Quality Alerts: 18 total (8 New, 5 In Progress, 5 Done)")
    print(f"  Quality Control Points: 5 created")
    print(f"  Quality Checks: 6 created (2 pending, 2 pass, 1 fail, 1 pending)")


if __name__ == "__main__":
    main()
