"""Stage 2: Join each ingested task with the GDP-grounded data.

Reads:
  data/raw_tasks.jsonl (Stage 1)
  data/env_to_product.json (env→product mapping)
  scaling_cua2 GDP CSVs (selected products + occupation_product_importance + product_totals)

Writes:
  data/tasks_with_gdp.jsonl

Per-task augmentation (when the env maps to a known product):
  gdp: {
    product, in_selected, tier?, total_gdp_usd?, categories[],
    soc_major_groups[], top_occupations[{occupation, share_pct, gdp_usd}],
    trainability?, pricing?, os_platforms?
  }

If the env doesn't map to any product, gdp is null. The visualizer still
indexes the task so the corpus stays complete.
"""

from __future__ import annotations

import ast
import csv
import json
import logging
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .jsonio import read_jsonl, write_jsonl
from .paths import (
    ENV_PRODUCT_MAP,
    RAW_TASKS,
    TASKS_WITH_GDP,
    gdp_dir,
)

logger = logging.getLogger(__name__)


def _parse_listish(value: str) -> List[str]:
    """The selected CSV stores list-like fields as Python literals."""
    if value is None:
        return []
    s = str(value).strip()
    if not s:
        return []
    if s.startswith("[") and s.endswith("]"):
        try:
            parsed = ast.literal_eval(s)
            if isinstance(parsed, (list, tuple)):
                return [str(x) for x in parsed]
        except (ValueError, SyntaxError):
            pass
    # Fallback: comma-split
    return [p.strip() for p in s.split(",") if p.strip()]


def _load_selected(gdp_root: Path) -> Dict[str, Dict[str, Any]]:
    """product → row from gym_anything_selected_products.csv."""
    out: Dict[str, Dict[str, Any]] = {}
    with (gdp_root / "gym_anything_selected_products.csv").open("r", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            try:
                gdp = float(row.get("product_total_gdp_usd") or 0.0)
            except ValueError:
                gdp = 0.0
            out[row["product"]] = {
                "tier": row.get("tier"),
                "substituted_for": row.get("substituted_for") or None,
                "total_gdp_usd": gdp,
                "categories": _parse_listish(row.get("category", "")),
                "soc_major_groups": _parse_listish(row.get("soc_major_group", "")),
                "trainability": row.get("trainability"),
                "pricing": row.get("pricing"),
                "os_platforms": [
                    p.strip() for p in (row.get("os_platforms") or "").split(",") if p.strip()
                ],
            }
    return out


def _load_totals(gdp_root: Path) -> Dict[str, Dict[str, Any]]:
    """product → aggregated totals (categories + GDP) from product_totals.csv."""
    by_product: Dict[str, Dict[str, Any]] = {}
    with (gdp_root / "gdp_weighting" / "product_totals.csv").open("r", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            p = row["product"]
            try:
                gdp = float(row.get("total_gdp_usd") or 0.0)
            except ValueError:
                gdp = 0.0
            try:
                occ_count = int(float(row.get("occupations") or 0))
            except ValueError:
                occ_count = 0
            entry = by_product.setdefault(
                p, {"total_gdp_usd": 0.0, "categories": [], "occupation_count_max": 0}
            )
            entry["total_gdp_usd"] += gdp
            cat = row.get("category")
            if cat and cat not in entry["categories"]:
                entry["categories"].append(cat)
            if occ_count > entry["occupation_count_max"]:
                entry["occupation_count_max"] = occ_count
    return by_product


def _load_top_occupations(gdp_root: Path, top_n: int = 15) -> Dict[str, List[Dict[str, Any]]]:
    """product → list of top occupations by attributed GDP."""
    by_product: Dict[str, List[Tuple[float, str, str, float, str]]] = defaultdict(list)
    occ_total: Dict[str, float] = {}

    # Build occupation totals to compute share %
    with (gdp_root.parent / "us_gdp_by_occupation_USD.csv").open("r", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            try:
                occ_total[row["occupation_title"]] = float(row.get("gdp_total") or 0.0)
            except ValueError:
                pass

    with (gdp_root / "gdp_weighting" / "occupation_product_importance.csv").open(
        "r", encoding="utf-8"
    ) as fh:
        for row in csv.DictReader(fh):
            p = row["product"]
            try:
                gdp = float(row.get("product_gdp_usd") or 0.0)
            except ValueError:
                gdp = 0.0
            occ = row.get("occupation_title", "")
            cat = row.get("category", "")
            soc = row.get("onetsoc", "")
            by_product[p].append((gdp, occ, soc, occ_total.get(occ, 0.0), cat))

    out: Dict[str, List[Dict[str, Any]]] = {}
    for p, items in by_product.items():
        items.sort(reverse=True, key=lambda x: x[0])
        topped: List[Dict[str, Any]] = []
        seen = set()
        for gdp, occ, soc, total, cat in items:
            if occ in seen:
                continue
            seen.add(occ)
            share = (gdp / total * 100.0) if total else 0.0
            topped.append({
                "occupation": occ,
                "onetsoc": soc,
                "category": cat,
                "gdp_usd": round(gdp, 2),
                "share_pct": round(share, 2),
            })
            if len(topped) >= top_n:
                break
        out[p] = topped
    return out


def _build_gdp_block(
    product: Optional[str],
    in_selected: bool,
    selected: Dict[str, Dict[str, Any]],
    totals: Dict[str, Dict[str, Any]],
    top_occs: Dict[str, List[Dict[str, Any]]],
) -> Optional[Dict[str, Any]]:
    if not product:
        return None
    sel = selected.get(product)
    tot = totals.get(product)

    if sel is None and tot is None:
        # Product was named in our manual override but not in either CSV.
        return {
            "product": product,
            "in_selected": False,
            "tier": None,
            "total_gdp_usd": None,
            "categories": [],
            "soc_major_groups": [],
            "trainability": None,
            "pricing": None,
            "os_platforms": [],
            "top_occupations": [],
            "data_source": "name_only",
        }

    block: Dict[str, Any] = {
        "product": product,
        "in_selected": in_selected,
        "data_source": "selected" if sel else "totals",
    }
    if sel:
        block.update({
            "tier": sel.get("tier"),
            "substituted_for": sel.get("substituted_for"),
            "total_gdp_usd": sel.get("total_gdp_usd"),
            "categories": sel.get("categories", []),
            "soc_major_groups": sel.get("soc_major_groups", []),
            "trainability": sel.get("trainability"),
            "pricing": sel.get("pricing"),
            "os_platforms": sel.get("os_platforms", []),
        })
    else:
        block.update({
            "tier": None,
            "total_gdp_usd": tot.get("total_gdp_usd") if tot else None,
            "categories": (tot or {}).get("categories", []),
            "soc_major_groups": [],
            "trainability": None,
            "pricing": None,
            "os_platforms": [],
        })
    block["top_occupations"] = top_occs.get(product, [])[:15]
    return block


def run(
    raw_tasks: Optional[Path] = None,
    env_map: Optional[Path] = None,
    output: Optional[Path] = None,
) -> int:
    if raw_tasks is None:
        raw_tasks = RAW_TASKS
    if env_map is None:
        env_map = ENV_PRODUCT_MAP
    if output is None:
        output = TASKS_WITH_GDP
    if not raw_tasks.is_file():
        raise RuntimeError(f"missing raw tasks: {raw_tasks}. Run ingest first.")
    if not env_map.is_file():
        raise RuntimeError(f"missing env→product map: {env_map}. Run env_to_product first.")

    mapping = json.loads(env_map.read_text(encoding="utf-8"))["map"]
    gdp_root = gdp_dir()
    selected = _load_selected(gdp_root)
    totals = _load_totals(gdp_root)
    top_occs = _load_top_occupations(gdp_root, top_n=15)

    n = 0
    n_with_gdp = 0
    n_with_full_selected = 0
    out_records = []
    for rec in read_jsonl(raw_tasks):
        env_id = rec["env_id"]
        m = mapping.get(env_id, {})
        product = m.get("product")
        in_selected = bool(m.get("in_selected"))
        gdp_block = _build_gdp_block(product, in_selected, selected, totals, top_occs)
        rec["gdp"] = gdp_block
        rec["env_product_match"] = {
            "product": product,
            "method": m.get("method"),
            "confidence": m.get("confidence"),
        }
        out_records.append(rec)
        n += 1
        if gdp_block is not None:
            n_with_gdp += 1
            if in_selected:
                n_with_full_selected += 1

    write_jsonl(output, out_records)
    logger.info(
        "GDP join: %d tasks total; %d with GDP block; %d in selected (rich) → %s",
        n, n_with_gdp, n_with_full_selected, output,
    )
    return n


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    print(run())
