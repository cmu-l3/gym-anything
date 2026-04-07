#!/usr/bin/env python3
"""Parse Derby ij output into structured JSON for wine_dinner_event_setup verification."""
import json
import re
import sys


def split_sections(text, marker_prefix="---M_"):
    """Split ij output into named sections using marker queries."""
    sections = {}
    current_key = None
    current_lines = []
    for line in text.split("\n"):
        if marker_prefix in line:
            if current_key is not None:
                sections[current_key] = "\n".join(current_lines)
            # Extract key: e.g. "---M_TAX---" -> "TAX"
            match = re.search(r"---M_(\w+)---", line)
            if match:
                current_key = match.group(1)
                current_lines = []
            else:
                current_key = None
        else:
            current_lines.append(line)
    if current_key is not None:
        sections[current_key] = "\n".join(current_lines)
    return sections


def parse_rows(section_text):
    """Parse ij tabular output into list of row tuples."""
    rows = []
    past_header = False
    past_sep = False
    for raw in section_text.split("\n"):
        line = raw.strip()
        if not line:
            continue
        lower = line.lower()
        # Skip ij metadata lines
        if "ij version" in lower or "apache derby" in lower:
            continue
        # Strip ij> prompts but keep the rest of the line
        if "ij>" in lower:
            line = re.sub(r"(?i)ij>\s*", "", line).strip()
            if not line:
                continue
        if "rows selected" in lower or "row selected" in lower or "0 rows" in lower:
            # Reset for next result set within same section
            past_header = False
            past_sep = False
            continue
        if "error" in lower or "url attribute" in lower:
            continue
        if "|" not in line:
            continue
        parts = [p.strip() for p in line.split("|")]
        parts = [p for p in parts if p is not None]
        if not past_header:
            past_header = True
            continue  # skip column header row
        if past_header and not past_sep:
            stripped = line.replace("-", "").replace("+", "").replace("|", "").replace(" ", "")
            if stripped == "":
                past_sep = True
                continue  # skip separator row
            else:
                past_sep = True  # no separator, data starts immediately
        rows.append(parts)
    return rows


def main():
    ij_output_path = sys.argv[1]
    task_start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    output_path = sys.argv[3] if len(sys.argv) > 3 else "/tmp/wine_dinner_result.json"

    with open(ij_output_path, "r") as f:
        full_output = f.read()

    sections = split_sections(full_output)

    taxes = parse_rows(sections.get("TAX", ""))
    categories = parse_rows(sections.get("CATEGORY", ""))
    groups = parse_rows(sections.get("GROUP", ""))
    items = parse_rows(sections.get("ITEM", ""))
    mod_groups = parse_rows(sections.get("MODGROUP", ""))
    modifiers = parse_rows(sections.get("MODIFIER", ""))
    links = parse_rows(sections.get("LINK", ""))
    tickets = parse_rows(sections.get("TICKET", ""))
    ticket_items = parse_rows(sections.get("TICKETITEM", ""))
    transactions = parse_rows(sections.get("TRANSACTION", ""))

    result = {
        "task_start": task_start,
        "taxes": [{"id": r[0], "name": r[1], "rate": r[2]} for r in taxes if len(r) >= 3],
        "categories": [{"id": r[0], "name": r[1]} for r in categories if len(r) >= 2],
        "groups": [
            {"id": r[0], "name": r[1], "category_id": r[2],
             "category_name": r[3] if len(r) > 3 else ""}
            for r in groups if len(r) >= 3
        ],
        "items": [
            {"id": r[0], "name": r[1], "price": r[2],
             "tax_id": r[3] if len(r) > 3 else "",
             "group_id": r[4] if len(r) > 4 else "",
             "tax_name": r[5] if len(r) > 5 else "",
             "group_name": r[6] if len(r) > 6 else ""}
            for r in items if len(r) >= 3
        ],
        "modifier_groups": [
            {"id": r[0], "name": r[1], "enabled": r[2] if len(r) > 2 else ""}
            for r in mod_groups if len(r) >= 2
        ],
        "modifiers": [
            {"id": r[0], "name": r[1], "price": r[2] if len(r) > 2 else "",
             "group_id": r[3] if len(r) > 3 else "",
             "group_name": r[4] if len(r) > 4 else ""}
            for r in modifiers if len(r) >= 2
        ],
        "item_modifier_links": [
            {"item_id": r[0], "group_id": r[1] if len(r) > 1 else "",
             "min_quantity": r[2] if len(r) > 2 else "",
             "max_quantity": r[3] if len(r) > 3 else "",
             "item_name": r[4] if len(r) > 4 else "",
             "group_name": r[5] if len(r) > 5 else ""}
            for r in links
        ],
        "tickets": [
            {"id": r[0], "type": r[1] if len(r) > 1 else "",
             "settled": r[2] if len(r) > 2 else "",
             "paid": r[3] if len(r) > 3 else "",
             "total_price": r[4] if len(r) > 4 else "",
             "create_date": r[5] if len(r) > 5 else ""}
            for r in tickets if len(r) >= 1
        ],
        "ticket_items": [
            {"ticket_id": r[0], "name": r[1] if len(r) > 1 else "",
             "price": r[2] if len(r) > 2 else "",
             "count": r[3] if len(r) > 3 else ""}
            for r in ticket_items if len(r) >= 1
        ],
        "transactions": [
            {"ticket_id": r[0], "payment_type": r[1] if len(r) > 1 else "",
             "amount": r[2] if len(r) > 2 else "",
             "type": r[3] if len(r) > 3 else ""}
            for r in transactions if len(r) >= 1
        ],
        "screenshot_path": "/tmp/task_final.png",
    }

    with open(output_path, "w") as f:
        json.dump(result, f, indent=2)

    print(f"Result written: {output_path}")
    print(f"Taxes: {len(result['taxes'])}")
    print(f"Categories: {len(result['categories'])}")
    print(f"Groups: {len(result['groups'])}")
    print(f"Items: {len(result['items'])}")
    print(f"Modifier groups: {len(result['modifier_groups'])}")
    print(f"Modifiers: {len(result['modifiers'])}")
    print(f"Item-modifier links: {len(result['item_modifier_links'])}")
    print(f"Tickets: {len(result['tickets'])}")
    print(f"Ticket items: {len(result['ticket_items'])}")
    print(f"Transactions: {len(result['transactions'])}")


if __name__ == "__main__":
    main()
