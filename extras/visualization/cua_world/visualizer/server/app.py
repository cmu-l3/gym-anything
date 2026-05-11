"""Quart server for the CUA-World visualizer.

Endpoints:
    GET  /                                 → web/index.html
    GET  /static/<path>                    → web/<path>
    GET  /api/search?q=...                 → hybrid search
    GET  /api/task/<env>/<task>            → full task detail
    GET  /api/favorites                    → curated showcase tasks
    GET  /api/facets                       → filter dropdown vocab
    GET  /api/software                     → all envs (sorted)
    GET  /api/software/<env_id>            → env detail + its tasks
    GET  /api/occupations                  → SOC groups + top occupations
    GET  /api/occupations/<key>            → occupation drill-down
    GET  /api/insights                     → GDP rollups for the Insights tab
    GET  /api/meta                         → index metadata

Loads the index once at startup. Quart is async so the search calls run on
the event loop's executor.
"""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Dict, Optional

from quart import Quart, jsonify, request, send_from_directory
from quart_cors import cors

from ..pipeline.paths import FAVORITES, VISUALIZER_ROOT, WEB_DIR
from .search import SearchIndex

logger = logging.getLogger(__name__)


def _load_favorites(index: SearchIndex) -> Dict[str, Any]:
    """Read favorites.json and resolve each entry to its full task record."""
    if not FAVORITES.is_file():
        return {"items": [], "blurb": ""}
    payload = json.loads(FAVORITES.read_text(encoding="utf-8"))
    items_in = payload.get("items") or []
    resolved = []
    for entry in items_in:
        env_id = entry.get("env_id")
        task_id = entry.get("task_id")
        task = index.get_task(env_id, task_id) if (env_id and task_id) else None
        if task is None:
            # Keep the entry as a placeholder so curators can see the broken refs.
            resolved.append({
                "env_id": env_id,
                "task_id": task_id,
                "blurb": entry.get("blurb"),
                "missing": True,
            })
            continue
        resolved.append({
            "env_id": env_id,
            "task_id": task_id,
            "blurb": entry.get("blurb"),
            "task_name": task["task_name"],
            "product": task["product"],
            "intent": task["intent"],
            "summary": task["summary"],
            "soc_major_groups": task["soc_major_groups"],
            "is_long_horizon": task["is_long_horizon"],
            "complexity": task["complexity"],
            "task_kind": task["task_kind"],
            "missing": False,
        })
    return {
        "blurb": payload.get("blurb") or "",
        "items": resolved,
    }


def create_app(index: Optional[SearchIndex] = None) -> Quart:
    if index is None:
        index = SearchIndex()
    app = Quart(__name__, static_folder=None)
    app = cors(app, allow_origin="*")

    app.config["INDEX"] = index

    # ---- static frontend ----

    @app.route("/")
    async def root():
        return await send_from_directory(WEB_DIR, "index.html")

    @app.route("/static/<path:filename>")
    async def static_files(filename: str):
        return await send_from_directory(WEB_DIR, filename)

    # ---- API ----

    @app.route("/api/meta")
    async def api_meta():
        return jsonify({"meta": index.meta, "facets": index.facets})

    @app.route("/api/facets")
    async def api_facets():
        return jsonify(index.facets)

    @app.route("/api/search")
    async def api_search():
        q = request.args.get("q", "")
        try:
            topk = int(request.args.get("topk", "30"))
        except ValueError:
            topk = 30
        topk = max(1, min(topk, 200))
        exact = request.args.get("exact", "0") in ("1", "true", "True")
        diversify = request.args.get("diversify", "1") not in ("0", "false", "False")
        per_env_cap = int(request.args.get("per_env_cap", "3") or "3")
        long_h = request.args.get("long_horizon")

        kwargs: Dict[str, Any] = dict(
            topk=topk,
            exact=exact,
            diversify=diversify,
            per_env_cap=per_env_cap,
            filter_soc=request.args.get("soc") or None,
            filter_os=request.args.get("os") or None,
            filter_difficulty=request.args.get("difficulty") or None,
            filter_kind=request.args.get("kind") or None,
            filter_env=request.args.get("env") or None,
            filter_product=request.args.get("product") or None,
            filter_split=request.args.get("split") or None,
            filter_long_horizon=(
                None if long_h in (None, "", "any")
                else long_h in ("1", "true", "True")
            ),
        )
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(None, lambda: index.search(q, **kwargs))
        return jsonify(result)

    @app.route("/api/task/<env_id>/<task_id>")
    async def api_task(env_id: str, task_id: str):
        task = index.get_task(env_id, task_id)
        if task is None:
            return jsonify({"error": "not_found"}), 404
        env = index.envs.get(env_id, {})
        return jsonify({"task": task, "env": env})

    @app.route("/api/favorites")
    async def api_favorites():
        return jsonify(_load_favorites(index))

    @app.route("/api/software")
    async def api_software():
        sort = request.args.get("sort", "gdp")
        items = index.list_software(sort=sort)
        return jsonify({"items": items, "count": len(items)})

    @app.route("/api/software/<env_id>")
    async def api_software_one(env_id: str):
        detail = index.get_software(env_id)
        if detail is None:
            return jsonify({"error": "not_found"}), 404
        return jsonify(detail)

    @app.route("/api/occupations")
    async def api_occupations():
        return jsonify(index.list_occupations())

    @app.route("/api/occupations/<path:key>")
    async def api_occupation_one(key: str):
        return jsonify(index.get_occupation(key))

    @app.route("/api/insights")
    async def api_insights():
        return jsonify(index.insights())

    return app


def main(argv=None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="Run the CUA-World visualizer server.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true", help="open the browser when ready")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    logger.info("Loading search index from %s", VISUALIZER_ROOT / "data")
    index = SearchIndex()
    logger.info(
        "Loaded %d tasks across %d envs (embedding dim %d).",
        index.meta["n_tasks"], index.meta["n_envs"], index.meta["embedding_dim"],
    )

    app = create_app(index)
    if args.open:
        import threading
        import webbrowser

        def _opener():
            import time
            time.sleep(0.8)
            webbrowser.open(f"http://{args.host}:{args.port}/")

        threading.Thread(target=_opener, daemon=True).start()

    app.run(host=args.host, port=args.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
