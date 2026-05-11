"""extras dispatcher entry: visualization / cua_world / visualizer.

Reachable as:
    gym-anything-extras visualization cua_world visualizer <subcommand> [args]

Subcommands:
    index    — run the full indexing pipeline (ingest → gdp_join → enrich → embed → build_index)
    serve    — boot the Quart server (and optionally open the browser)
    favorites — print/edit favorites.json (helper)

Each subcommand has its own --help.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import List, Optional


LOGFMT = "%(asctime)s %(levelname)-7s %(name)s: %(message)s"


def _cmd_index(args) -> int:
    logging.basicConfig(level=logging.INFO, format=LOGFMT, datefmt="%H:%M:%S")
    from .pipeline import build_index, embed, enrich, env_to_product, gdp_join, ingest

    only = [s.strip() for s in (args.envs or "").split(",") if s.strip()] or None
    stages = set(args.stage) if args.stage else {"ingest", "map", "gdp", "enrich", "embed", "build"}

    if "ingest" in stages:
        n = ingest.run()
        print(f"  ingest: {n} tasks")
    if "map" in stages:
        r = env_to_product.run()
        print(f"  map: {r['n_envs']} envs, {r['n_unmatched']} unmatched")
    if "gdp" in stages:
        n = gdp_join.run()
        print(f"  gdp_join: {n} tasks")
    if "enrich" in stages:
        r = enrich.run(
            limit=args.limit,
            only_envs=only,
            concurrency=args.concurrency,
            batch_size=args.batch_size,
        )
        print(f"  enrich: {json.dumps(r)}")
    if "embed" in stages:
        r = embed.run(
            limit=args.limit,
            concurrency=args.embed_concurrency,
            batch_size=args.embed_batch,
        )
        print(f"  embed: {json.dumps(r)}")
    if "build" in stages:
        r = build_index.run()
        print(f"  build_index: {json.dumps(r)}")
    return 0


def _cmd_serve(args) -> int:
    from .server.app import main as server_main
    server_argv = ["--host", args.host, "--port", str(args.port)]
    if args.open:
        server_argv.append("--open")
    return server_main(server_argv)


def _cmd_compile(args) -> int:
    logging.basicConfig(level=logging.INFO, format=LOGFMT, datefmt="%H:%M:%S")
    from pathlib import Path

    from .pipeline import compile_static, embed_browser

    if args.skip_bge:
        logger.info("Skipping bge re-embed (per --skip-bge).")
    else:
        embed_browser.run()

    result = compile_static.run(
        dest=Path(args.dest).resolve() if args.dest else None,
    )
    print(json.dumps(result, indent=2))
    return 0


def _cmd_favorites(args) -> int:
    from .pipeline.paths import FAVORITES
    if args.print:
        if FAVORITES.is_file():
            print(FAVORITES.read_text(encoding="utf-8"))
        else:
            print(f"# {FAVORITES} does not exist yet.", file=sys.stderr)
        return 0
    print(f"Favorites file: {FAVORITES}")
    print(f"Edit with your editor of choice (e.g. $EDITOR {FAVORITES}).")
    return 0


def run(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gym-anything-extras visualization cua_world visualizer",
        description="CUA-World benchmark task visualizer.",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_index = sub.add_parser("index", help="run the indexing pipeline")
    p_index.add_argument(
        "--stage", action="append",
        choices=["ingest", "map", "gdp", "enrich", "embed", "build"],
        help="restrict to one or more stages (default: all)",
    )
    p_index.add_argument("--envs", help="comma-separated env_ids to limit to")
    p_index.add_argument("--limit", type=int, help="limit total tasks (debug)")
    p_index.add_argument("--concurrency", type=int, default=12, help="LLM concurrency")
    p_index.add_argument("--batch-size", type=int, default=5, help="LLM batch size")
    p_index.add_argument("--embed-concurrency", type=int, default=8)
    p_index.add_argument("--embed-batch", type=int, default=64)
    p_index.set_defaults(func=_cmd_index)

    p_serve = sub.add_parser("serve", help="boot the Quart server")
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8765)
    p_serve.add_argument("--open", action="store_true")
    p_serve.set_defaults(func=_cmd_serve)

    p_fav = sub.add_parser("favorites", help="show favorites.json path / contents")
    p_fav.add_argument("--print", action="store_true")
    p_fav.set_defaults(func=_cmd_favorites)

    p_compile = sub.add_parser("compile", help="bundle a self-contained static site into website/explore/")
    p_compile.add_argument("--dest", help="output directory (default: <repo>/website/explore)")
    p_compile.add_argument("--skip-bge", action="store_true",
                           help="don't re-encode the corpus with bge-small (use cached embeddings)")
    p_compile.set_defaults(func=_cmd_compile)

    args = parser.parse_args(argv)
    return args.func(args)
