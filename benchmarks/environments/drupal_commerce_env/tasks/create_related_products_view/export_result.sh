#!/bin/bash
set -e

echo "=== Exporting create_related_products_view result ==="

python3 <<'PY'
import json
import subprocess

RESULT_FILE = "/tmp/create_related_products_view_result.json"
score = 0
criteria = []


def add_criterion(name, points, passed, description):
    global score
    if passed:
        score += points
    criteria.append(
        {
            "name": name,
            "points": points,
            "passed": passed,
            "description": description,
        }
    )


def drush_get_config(config_name):
    try:
        cmd = [
            "/var/www/html/drupal/vendor/bin/drush",
            "--root=/var/www/html/drupal",
            "config:get",
            config_name,
            "--format=json",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)
    except Exception:
        return None


def check_view_config():
    view_config = drush_get_config("views.view.related_products")
    if not view_config:
        add_criterion("View Exists", 10, False, "View 'related_products' not found")
        add_criterion("Block Display", 10, False, "Cannot check display")
        add_criterion("Contextual Exclusion", 30, False, "Cannot check exclusion")
        add_criterion("Random Sort", 15, False, "Cannot check sort")
        add_criterion("Item Count", 15, False, "Cannot check count")
        return

    add_criterion("View Exists", 10, True, "View 'related_products' exists")

    displays = view_config.get("display", {})
    block_display_id = None
    for display_id, display_data in displays.items():
        if display_data.get("display_plugin") == "block":
            block_display_id = display_id
            break

    if block_display_id:
        add_criterion("Block Display", 10, True, "Block display found")
    else:
        add_criterion("Block Display", 10, False, "No block display found in view")
        return

    config_str = json.dumps(view_config)
    add_criterion(
        "Random Sort",
        15,
        '"id": "random"' in config_str or '"plugin_id": "random"' in config_str,
        "Random sort criterion found" if '"random"' in config_str else "Random sort not configured",
    )
    add_criterion(
        "Item Count",
        15,
        '"items_per_page": 3' in config_str or '"items_per_page": "3"' in config_str,
        "Pager set to 3 items"
        if '"items_per_page": 3' in config_str or '"items_per_page": "3"' in config_str
        else "Pager not set to 3 items",
    )

    exclusion_found = False

    def check_argument(args):
        for arg in args.values():
            if arg.get("default_action") == "default" and arg.get("default_argument_skip_url") is False:
                exclude = arg.get("exclude")
                if exclude is True or exclude == 1 or str(exclude).lower() == "true":
                    return True
        return False

    if check_argument(displays.get("default", {}).get("display_options", {}).get("arguments", {})):
        exclusion_found = True
    elif check_argument(displays.get(block_display_id, {}).get("display_options", {}).get("arguments", {})):
        exclusion_found = True

    add_criterion(
        "Contextual Exclusion",
        30,
        exclusion_found,
        "Contextual filter configured to Exclude"
        if exclusion_found
        else "Contextual filter exclusion not found",
    )


def check_block_placement():
    try:
        html = subprocess.run(
            ["curl", "-s", "http://localhost/product/1"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout
        placed = "view-id-related_products" in html
        add_criterion(
            "Block Placement",
            20,
            placed,
            "Block HTML found on product page"
            if placed
            else "Block HTML class 'view-id-related_products' not found on /product/1",
        )
    except Exception as exc:
        add_criterion("Block Placement", 20, False, f"Error verifying placement: {exc}")


check_view_config()
check_block_placement()

with open(RESULT_FILE, "w", encoding="utf-8") as f:
    json.dump({"score": score, "criteria": criteria}, f, indent=2)
PY

chmod 666 /tmp/create_related_products_view_result.json
cat /tmp/create_related_products_view_result.json
echo "=== Export complete ==="
