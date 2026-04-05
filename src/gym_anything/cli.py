from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from .api import from_config
from .compatibility import (
    get_runner_compatibility,
    get_runner_compatibility_matrix,
    render_compatibility_text,
)
from .doctor import render_doctor_text, render_doctor_rich, run_doctor
from .verification import (
    build_missing_hook_reference_manifest,
    build_task_status_manifest,
    build_verified_task_split,
    render_summary_text,
    verify_corpus,
    verify_environment_dir,
    write_json_report,
)
from .verification.pipeline import verify_task_pipeline
from .verification.reports import render_task_pipeline_result_text

_ENV_SEARCH_PATHS = [
    "benchmarks/cua_world/environments",
]


def _resolve_env_dir(name: str) -> str:
    """Resolve a short env name (e.g. 'moodle_env') to its full path."""
    # Already a valid path
    if Path(name).is_dir() and (Path(name) / "env.json").exists():
        return name
    # Search standard locations
    for base in _ENV_SEARCH_PATHS:
        candidate = Path(base) / name
        if candidate.is_dir() and (candidate / "env.json").exists():
            return str(candidate)
    # Fuzzy: try appending _env
    if not name.endswith("_env"):
        return _resolve_env_dir(name + "_env")
    print(f"Error: environment '{name}' not found.", file=sys.stderr)
    print(f"Run 'gym-anything list' to see available environments.", file=sys.stderr)
    sys.exit(1)


def _print_json(data) -> None:
    print(json.dumps(data, indent=2, sort_keys=True))


def _show_rich_help() -> None:
    """Display a rich help panel with grouped commands."""
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table

    console = Console()

    commands = Table(show_header=False, box=None, padding=(0, 2))
    commands.add_column("Command", style="bold cyan")
    commands.add_column("Description")

    commands.add_row("run", "Run an environment (interactive or headless)")
    commands.add_row("benchmark", "Run agent evaluation on benchmark tasks")
    commands.add_row("list", "List available environments")
    commands.add_row("agents", "List available agent implementations")
    commands.add_row("")
    commands.add_row("doctor", "Check system prerequisites")
    commands.add_row("compatibility", "Show runner compatibility matrix")
    commands.add_row("cache", "List or purge cached VM images and SDKs")
    commands.add_row("")
    commands.add_row("verify spec", "Verify one environment and its task specs")
    commands.add_row("verify corpus", "Verify all specs under a root")
    commands.add_row("verify task", "Run a task through reset/finalize pipeline")
    commands.add_row("validate", "Quick-check env/task spec validity")

    panel = Panel(
        commands,
        title="[bold]gym-anything[/bold]",
        subtitle="[dim]Use gym-anything <command> --help for details[/dim]",
        border_style="blue",
        padding=(1, 2),
    )
    console.print()
    console.print(panel)


def cmd_verify_spec(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    summary = verify_environment_dir(args.env_dir, task_id=args.task)
    if args.json:
        _print_json(summary.to_dict())
    else:
        print(render_summary_text(summary))
    return 0 if summary.ok else 1


def cmd_verify_corpus(args):
    summary = verify_corpus(args.root, max_failures=args.max_failures)
    if args.write_status_manifest:
        write_json_report(build_task_status_manifest(summary), args.write_status_manifest)
    if args.write_verified_split:
        write_json_report(build_verified_task_split(summary), args.write_verified_split)
    if args.write_missing_hook_manifest:
        write_json_report(build_missing_hook_reference_manifest(summary), args.write_missing_hook_manifest)
    if args.json:
        _print_json(summary.to_dict())
    else:
        print(render_summary_text(summary))
    return 0 if summary.ok else 1


def cmd_verify_task(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    result = verify_task_pipeline(
        env_dir=args.env_dir,
        task_id=args.task,
        seed=args.seed,
        use_cache=args.use_cache,
        cache_level=args.cache_level,
        use_savevm=args.use_savevm,
    )
    if args.json:
        _print_json(result.to_dict())
    else:
        print(render_task_pipeline_result_text(result))
    return 0 if result.ok else 1


def cmd_validate(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    summary = verify_environment_dir(args.env_dir, task_id=args.task)
    if summary.ok:
        first_task = next((record.spec_id for record in summary.records if record.kind == "task"), None)
        env_id = next((record.spec_id for record in summary.records if record.kind == "env"), None)
        print("Spec OK:", env_id, "task=", first_task)
        return 0
    print(render_summary_text(summary), file=sys.stderr)
    return 1


def _pick_random_task(env_dir: str) -> str:
    """Pick a random task from the environment's tasks directory."""
    import random
    tasks_dir = Path(env_dir) / "tasks"
    if not tasks_dir.is_dir():
        return None
    tasks = [t.name for t in tasks_dir.iterdir() if t.is_dir()]
    if not tasks:
        return None
    chosen = random.choice(tasks)
    return chosen


def cmd_run(args):
    args.env_dir = _resolve_env_dir(args.env_dir)
    if not args.task:
        args.task = _pick_random_task(args.env_dir)
        if args.task:
            print(f"No task specified, randomly selected: {args.task}")
    env = from_config(args.env_dir, task_id=args.task)

    if args.interactive:
        from .tui.progress import create_reporter
        from .tui.session import InteractiveSession

        env_name = Path(args.env_dir).name
        reporter = create_reporter(env_name=env_name, task_name=args.task or "")
        env.set_reporter(reporter)

        reporter.define_stages([
            ("instance", "Initializing instance"),
            ("base_image", "Base image check"),
            ("cow_overlay", "COW overlay"),
            ("networking", "Network setup"),
            ("vm_launch", "Launching VM"),
            ("port_forward", "Port forwarding"),
            ("ssh_wait", "Waiting for SSH"),
            ("rosetta", "Rosetta setup"),
            ("desktop_wait", "Waiting for desktop"),
            ("vnc_setup", "VNC setup"),
            ("mounts", "File mounts"),
            ("pre_start_hook", "Pre-start hook"),
            ("post_start_hook", "Post-start hook"),
            ("pre_task_hook", "Pre-task hook"),
            ("ready", "Ready"),
        ])

        with reporter:
            obs = env.reset(seed=args.seed)

        session = InteractiveSession(env, auto_open_vnc=getattr(args, "open_vnc", False))
        session.run()
        return 0

    # Non-interactive mode: run steps
    obs = env.reset(seed=args.seed)
    print("Episode started. Artifacts will be saved under:", env.episode_dir)
    steps = args.steps or (env.task_spec.init.max_steps if env.task_spec else 10)
    for i in range(steps):
        if i == 9:
            if args.debug:
                breakpoint()
        obs, reward, done, info = env.step({})
        if done:
            break
        time.sleep(0.2)
    if args.debug:
        breakpoint()
    episode_dir = env.episode_dir
    env.close()
    print("Episode finished. See:", episode_dir)
    return 0


def cmd_compatibility(args):
    if args.runner:
        compatibilities = [get_runner_compatibility(args.runner)]
    else:
        compatibilities = get_runner_compatibility_matrix()
    if args.json:
        _print_json([item.to_dict() for item in compatibilities])
        return 0

    from rich.console import Console
    from rich.table import Table

    console = Console()

    table = Table(title="Runner Compatibility Matrix", title_style="bold")
    table.add_column("Runner", style="bold cyan")
    table.add_column("Live Recording", justify="center")
    table.add_column("Video Assembly", justify="center")
    table.add_column("Caching", justify="center")
    table.add_column("SaveVM", justify="center")
    table.add_column("User Accounts", justify="center")

    def _yn(val: bool) -> str:
        return "[green]Yes[/green]" if val else "[red]No[/red]"

    _ACCOUNT_STYLE = {
        "provision_from_spec": "[green]provision_from_spec[/green]",
        "preprovisioned_accounts": "[yellow]preprovisioned[/yellow]",
        "metadata_only": "[dim]metadata_only[/dim]",
        "unsupported": "[red]unsupported[/red]",
    }

    for c in compatibilities:
        table.add_row(
            f"{c.display_name}\n[dim]{c.runner}[/dim]",
            _yn(c.live_recording),
            _yn(c.screenshot_video_assembly),
            _yn(c.checkpoint_caching),
            _yn(c.savevm),
            _ACCOUNT_STYLE.get(c.user_accounts_mode, c.user_accounts_mode),
        )

    console.print()
    console.print(table)

    # Print notes beneath the table
    has_notes = any(c.notes for c in compatibilities)
    if has_notes:
        console.print()
        for c in compatibilities:
            if c.notes:
                console.print(f"  [bold]{c.runner}[/bold]")
                for note in c.notes:
                    console.print(f"    [dim]-[/dim] {note}")

    return 0


def cmd_list(args):
    from rich.console import Console
    from rich.table import Table

    console = Console()
    found_any = False

    for base in _ENV_SEARCH_PATHS:
        base_path = Path(base)
        if not base_path.is_dir():
            continue
        envs = sorted(
            d.name for d in base_path.iterdir()
            if d.is_dir() and (d / "env.json").exists()
        )
        if not envs:
            continue

        found_any = True

        table = Table(title=f"Environments  [dim]({base})[/dim]", title_style="bold")
        table.add_column("Environment", style="bold cyan")
        table.add_column("Tasks", justify="right")

        for env_name in envs:
            env_dir = base_path / env_name
            tasks = sorted(
                t.name for t in (env_dir / "tasks").iterdir()
                if t.is_dir()
            ) if (env_dir / "tasks").is_dir() else []

            if args.verbose and tasks:
                task_list = "\n".join(f"[dim]-[/dim] {t}" for t in tasks)
                table.add_row(env_name, f"{len(tasks)}\n{task_list}")
            else:
                table.add_row(env_name, str(len(tasks)))

        console.print()
        console.print(table)

    if not found_any:
        console.print("[yellow]No environments found.[/yellow]")

    return 0


def _build_agent_args(args) -> dict:
    """Construct the agent_args dict from individual CLI flags."""
    agent_args = {}
    if args.model:
        agent_args["model"] = args.model
    if getattr(args, "exp_name", None):
        agent_args["exp_name"] = args.exp_name
    else:
        agent_name = args.agent.lower().replace("agent", "")
        model_short = (args.model or "default").split("/")[-1]
        agent_args["exp_name"] = f"{agent_name}-{model_short}"
    if args.task:
        agent_args["task_name"] = args.task
    if getattr(args, "temperature", None) is not None:
        agent_args["temperature"] = args.temperature
    for kv in (getattr(args, "agent_arg", None) or []):
        key, _, value = kv.partition("=")
        try:
            value = json.loads(value)
        except (json.JSONDecodeError, ValueError):
            pass
        agent_args[key] = value
    return agent_args


def _run_benchmark_batch(args) -> int:
    """Run benchmark in batch mode across multiple tasks."""
    from benchmarks.cua_world.registry import (
        get_tasks_for_environment,
        load_environment_task_splits,
        resolve_environment_dir,
        resolve_environment_key,
    )

    if args.env_dir == "all":
        registry = load_environment_task_splits(surface=args.surface)
        pairs = []
        for env_key, split_map in registry.items():
            if args.split not in split_map:
                continue
            env_dir = str(resolve_environment_dir(env_key))
            for task_id in split_map[args.split]:
                pairs.append((task_id, env_dir))
    else:
        env_key = resolve_environment_key(args.env_dir)
        tasks = get_tasks_for_environment(env_key, split=args.split, surface=args.surface)
        pairs = [(task_id, args.env_dir) for task_id in tasks]

    if not pairs:
        print(f"No tasks found for split '{args.split}'.", file=sys.stderr)
        return 1

    print(f"Running {len(pairs)} tasks with {args.agent}")
    failures = 0
    for i, (task_id, env_dir) in enumerate(pairs, 1):
        print(f"\n[{i}/{len(pairs)}] {Path(env_dir).name} / {task_id}")
        cmd = [
            sys.executable, "-m", "gym_anything.cli", "benchmark",
            env_dir, "--task", task_id,
            "--agent", args.agent,
            "--seed", str(args.seed),
            "--cache-level", args.cache_level,
        ]
        if args.steps is not None:
            cmd.extend(["--steps", str(args.steps)])
        if args.model:
            cmd.extend(["--model", args.model])
        if getattr(args, "exp_name", None):
            cmd.extend(["--exp-name", args.exp_name])
        if args.use_cache:
            cmd.append("--use-cache")
        if args.use_savevm:
            cmd.append("--use-savevm")
        if getattr(args, "temperature", None) is not None:
            cmd.extend(["--temperature", str(args.temperature)])
        for kv in (getattr(args, "agent_arg", None) or []):
            cmd.extend(["--agent-arg", kv])

        result = subprocess.run(cmd, check=False)
        if result.returncode != 0:
            failures += 1

    print(f"\nBatch complete: {len(pairs) - failures}/{len(pairs)} succeeded")
    return 1 if failures else 0


def cmd_benchmark(args) -> int:
    try:
        from agents.evaluation.run_single import run_single as _run_single
    except ImportError:
        print("Error: agent dependencies not installed.", file=sys.stderr)
        print("Run: pip install -e '.[agents]'", file=sys.stderr)
        return 1

    if args.env_dir != "all":
        args.env_dir = _resolve_env_dir(args.env_dir)

    if not args.task:
        return _run_benchmark_batch(args)

    # Rich header for single-task benchmark run
    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table

    console = Console()

    info = Table(show_header=False, box=None, padding=(0, 1))
    info.add_column("Key", style="dim")
    info.add_column("Value", style="bold")
    info.add_row("Environment", Path(args.env_dir).name)
    info.add_row("Task", args.task)
    info.add_row("Agent", args.agent)
    info.add_row("Model", args.model or "[dim]default[/dim]")
    info.add_row("Max steps", str(args.steps) if args.steps is not None else "[dim]from task.json[/dim]")
    info.add_row("Seed", str(args.seed))

    console.print()
    console.print(Panel(
        info,
        title="[bold]Benchmark Run[/bold]",
        border_style="green",
        padding=(1, 2),
    ))
    console.print()

    agent_args = _build_agent_args(args)
    ns = argparse.Namespace(
        env_dir=args.env_dir,
        seed=args.seed,
        task=args.task,
        steps=args.steps,
        agent=args.agent,
        agent_args=json.dumps(agent_args),
        debug=args.debug,
        debug_low=False,
        verbose=args.verbose,
        setup_code="auto",
        use_cache=args.use_cache,
        cache_level=args.cache_level,
        use_savevm=args.use_savevm,
        vlm_backend=os.environ.get("VLM_BACKEND", "local"),
        vlm_base_url=os.environ.get("VLM_BASE_URL", "http://localhost:8080/v1"),
        vlm_model=os.environ.get("VLM_MODEL", "Qwen/Qwen3-VL-4B-Thinking"),
    )
    return _run_single(ns)


_CACHE_ROOT = Path.home() / ".cache" / "gym-anything"

# Base files/dirs inside qemu/ that are expensive to rebuild.
# Anything else in qemu/ (and qemu/avf/) is treated as work.
_QEMU_BASE_NAMES = {
    "base_ubuntu_gnome_arm64.qcow2",
    "base_ubuntu_gnome_arm64.raw",
    "base_ubuntu_gnome.qcow2",
    "ubuntu-cloud-arm64.img",
    "ubuntu-cloud.img",
}


def _cache_size(path: Path) -> int:
    """Return actual disk usage of a path in bytes (handles sparse files)."""
    if not path.exists():
        return 0
    try:
        if path.is_file():
            return path.stat().st_blocks * 512
    except (OSError, AttributeError):
        return 0
    total = 0
    for entry in path.rglob("*"):
        try:
            if entry.is_file():
                total += entry.stat().st_blocks * 512
        except (OSError, FileNotFoundError, AttributeError):
            pass
    return total


def _format_size(num_bytes: int) -> str:
    n = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


def _collect_qemu_work_paths() -> list[Path]:
    """Return paths inside qemu/ that are work (not base images)."""
    qemu = _CACHE_ROOT / "qemu"
    if not qemu.exists():
        return []
    paths = []
    for entry in qemu.iterdir():
        if entry.name in _QEMU_BASE_NAMES:
            continue
        if entry.name == "avf":
            # Descend into avf/ to separate base from work
            for sub in entry.iterdir():
                if sub.name not in _QEMU_BASE_NAMES:
                    paths.append(sub)
            continue
        if entry.name.endswith(".log"):
            paths.append(entry)
            continue
        paths.append(entry)
    return paths


def _collect_qemu_base_paths() -> list[Path]:
    """Return paths inside qemu/ that are base images."""
    qemu = _CACHE_ROOT / "qemu"
    if not qemu.exists():
        return []
    paths = []
    for entry in qemu.rglob("*"):
        if entry.name in _QEMU_BASE_NAMES and entry.is_file():
            paths.append(entry)
    return paths


def _cache_components() -> list[dict]:
    """Return list of cache components with category (work/base)."""
    return [
        {
            "name": "qemu-work",
            "category": "work",
            "paths": _collect_qemu_work_paths(),
            "desc": "QEMU/AVF work directories and COW overlays (per-run state)",
        },
        {
            "name": "avd-checkpoints",
            "category": "work",
            "paths": [_CACHE_ROOT / "avd-checkpoints"],
            "desc": "AVD checkpoint snapshots",
        },
        {
            "name": "containers",
            "category": "work",
            "paths": [_CACHE_ROOT / "containers"],
            "desc": "Container runtime cache",
        },
        {
            "name": "apptainer",
            "category": "work",
            "paths": [_CACHE_ROOT / "apptainer"],
            "desc": "Apptainer SIF images and overlays",
        },
        {
            "name": "qemu-base",
            "category": "base",
            "paths": _collect_qemu_base_paths(),
            "desc": "QEMU/AVF base VM images (~5 min to rebuild)",
        },
        {
            "name": "android-sdk",
            "category": "base",
            "paths": [_CACHE_ROOT / "android-sdk"],
            "desc": "Android SDK (requires network to re-download)",
        },
        {
            "name": "apks",
            "category": "base",
            "paths": [_CACHE_ROOT / "apks"],
            "desc": "Downloaded Android APKs",
        },
        {
            "name": "avd",
            "category": "base",
            "paths": [_CACHE_ROOT / "avd"],
            "desc": "Android Virtual Device definitions",
        },
    ]


def _component_size(component: dict) -> int:
    return sum(_cache_size(p) for p in component["paths"])


def cmd_cache_list(args) -> int:
    from rich.console import Console
    from rich.table import Table

    console = Console()

    if not _CACHE_ROOT.exists():
        console.print(f"[dim]Cache directory does not exist: {_CACHE_ROOT}[/]")
        return 0

    components = _cache_components()

    table = Table(title=f"Cache at {_CACHE_ROOT}")
    table.add_column("Component", style="cyan")
    table.add_column("Category", style="bold")
    table.add_column("Size", justify="right", style="green")
    table.add_column("Description", style="dim")

    total_work = 0
    total_base = 0
    for comp in components:
        size = _component_size(comp)
        if comp["category"] == "work":
            total_work += size
            cat_style = "[yellow]work[/]"
        else:
            total_base += size
            cat_style = "[blue]base[/]"
        size_str = _format_size(size) if size > 0 else "[dim]--[/]"
        table.add_row(comp["name"], cat_style, size_str, comp["desc"])

    console.print(table)
    console.print(f"\n[bold yellow]Work[/] (safe to purge, recreated per run):  [green]{_format_size(total_work)}[/]")
    console.print(f"[bold blue]Base[/] (expensive to rebuild/re-download):    [green]{_format_size(total_base)}[/]")
    console.print(f"[bold]Total:[/]                                        [green]{_format_size(total_work + total_base)}[/]")
    return 0


def cmd_cache_purge(args) -> int:
    import shutil
    from rich.console import Console

    console = Console()

    if not _CACHE_ROOT.exists():
        console.print(f"[dim]Cache directory does not exist: {_CACHE_ROOT}[/]")
        return 0

    components = _cache_components()

    # Determine which components to purge
    if args.component:
        # Specific component or category
        if args.component in ("work", "base"):
            components = [c for c in components if c["category"] == args.component]
        else:
            components = [c for c in components if c["name"] == args.component]
            if not components:
                console.print(f"[red]Unknown cache component:[/] {args.component}")
                names = [c["name"] for c in _cache_components()]
                console.print(f"Known components: {', '.join(names)}")
                console.print(f"Or categories: work, base")
                return 1
    elif args.all:
        pass  # keep all components
    else:
        # Default: work only
        components = [c for c in components if c["category"] == "work"]

    # Flatten to (name, path, size) tuples
    to_remove = []
    for comp in components:
        for path in comp["paths"]:
            if path.exists():
                to_remove.append((comp["name"], path, _cache_size(path)))

    if not to_remove:
        console.print("[dim]Nothing to purge.[/]")
        return 0

    total_size = sum(size for _, _, size in to_remove)

    # Confirm unless --yes
    if not args.yes:
        console.print("The following will be deleted:")
        for name, path, size in to_remove:
            console.print(f"  [cyan]{name}[/]  [green]{_format_size(size)}[/]  [dim]{path}[/]")
        console.print(f"\n[bold]Total to free:[/] [green]{_format_size(total_size)}[/]")
        reply = input("Proceed? [y/N] ").strip().lower()
        if reply not in ("y", "yes"):
            console.print("[dim]Aborted.[/]")
            return 0

    # Delete
    freed = 0
    failures = 0
    for name, path, size in to_remove:
        try:
            if path.is_file():
                path.unlink()
            else:
                shutil.rmtree(path)
            console.print(f"[green]✓[/] removed {path.name}  ({_format_size(size)})")
            freed += size
        except OSError as exc:
            console.print(f"[red]✗[/] failed to remove {path}: {exc}")
            failures += 1

    console.print(f"\n[bold green]Freed {_format_size(freed)}[/]")
    return 1 if failures else 0


def cmd_agents(args) -> int:
    try:
        import agents.agents as agent_module
    except ImportError:
        print("Error: agent dependencies not installed.", file=sys.stderr)
        print("Run: pip install -e '.[agents]'", file=sys.stderr)
        return 1

    names = sorted(getattr(agent_module, "__all__", []))
    if not names:
        print("No agents found.")
        return 0

    from rich.console import Console
    from rich.table import Table

    console = Console()

    table = Table(title="Available Agents", title_style="bold")
    table.add_column("#", style="dim", justify="right")
    table.add_column("Agent", style="bold cyan")

    for i, name in enumerate(names, 1):
        table.add_row(str(i), name)

    console.print()
    console.print(table)
    return 0


def cmd_doctor(args):
    report = run_doctor(
        runner=args.runner,
        verification_root=Path(args.verification_root) if args.verification_root else None,
    )
    if args.json:
        _print_json(report.to_dict())
        return 0 if report.ok else 1

    import platform as _platform

    from rich.console import Console
    from rich.panel import Panel
    from rich.table import Table

    console = Console()

    # Platform header
    platform_info = (
        f"[bold]Platform:[/bold] {sys.platform} ({_platform.machine()})  "
        f"[bold]Python:[/bold] {_platform.python_version()}"
    )
    console.print()
    console.print(Panel(platform_info, border_style="blue", padding=(0, 1)))

    # Runner status from the doctor module's get_runner_status
    from .doctor import get_runner_status

    runner_status = get_runner_status()

    status_table = Table(title="Runner Status", title_style="bold")
    status_table.add_column("Runner", style="bold cyan")
    status_table.add_column("Status", justify="center")
    status_table.add_column("Details")

    for runner_key, status in runner_status.items():
        reason = status.get("reason")
        if reason:
            status_table.add_row(
                runner_key,
                "[dim]--[/dim]",
                f"[dim]{reason}[/dim]",
            )
            continue

        available = status["available"]
        status_mark = "[green]READY[/green]" if available else "[red]MISSING DEPS[/red]"

        dep_lines = []
        for dep, info in status["deps"].items():
            if info["installed"]:
                dep_lines.append(f"[green]OK[/green] {dep}")
            else:
                dep_lines.append(f"[red]MISSING[/red] {dep}")
                if info.get("install"):
                    dep_lines.append(f"  [dim]{info['install']}[/dim]")

        status_table.add_row(
            runner_key,
            status_mark,
            "\n".join(dep_lines) if dep_lines else "[dim]no deps[/dim]",
        )

    console.print()
    console.print(status_table)

    # Check-level details
    checks_table = Table(title="Diagnostic Checks", title_style="bold")
    checks_table.add_column("Check", style="bold")
    checks_table.add_column("Result", justify="center")
    checks_table.add_column("Detail")

    for check in report.checks:
        if check.ok:
            mark = "[green]PASS[/green]"
        elif not check.required:
            mark = "[yellow]WARN[/yellow]"
        else:
            mark = "[red]FAIL[/red]"
        checks_table.add_row(check.name, mark, check.detail)

    console.print()
    console.print(checks_table)

    # Overall verdict
    console.print()
    if report.ok:
        console.print("[bold green]Overall: OK[/bold green]")
    else:
        console.print("[bold red]Overall: FAILED[/bold red]")

    # Offer interactive install for the recommended runner (or the one the
    # user asked about with --runner).
    _doctor_offer_install(
        console,
        runner_status,
        explicit_runner=args.runner,
        no_install=args.no_install,
    )

    return 0 if report.ok else 1


def _doctor_offer_install(
    console,
    runner_status,
    *,
    explicit_runner,
    no_install: bool,
) -> None:
    """Recommend a runner and offer to install missing deps interactively."""
    from .doctor import get_recommended_runner
    from .installers import get_install_plan, run_install_plan

    if explicit_runner is not None:
        target = explicit_runner
    else:
        target = get_recommended_runner(runner_status)
    if target is None:
        return

    status = runner_status.get(target, {})
    reason = status.get("reason")
    if reason:
        console.print()
        console.print(
            f"[yellow]Runner {target} is not available on this platform:[/yellow] {reason}"
        )
        return
    console.print()
    label = "Runner" if explicit_runner else "Recommended runner"
    if status.get("available"):
        console.print(f"[bold green]{label} ({target}) is ready.[/bold green]")
        return

    plan = get_install_plan(target)
    if plan is None:
        console.print(
            f"[yellow]{label}:[/yellow] {target}  "
            f"[dim](no automated installer yet — see docs for manual setup)[/dim]"
        )
        return

    console.print(f"[bold]{label}:[/bold] {plan.runner}")
    console.print(f"  [dim]{plan.summary}[/dim]")
    if plan.prereq_note:
        console.print(f"  [dim]{plan.prereq_note}[/dim]")

    if plan.manual_only:
        console.print()
        for line in plan.manual_only.splitlines():
            console.print(f"  {line}")
        return

    console.print()
    console.print("[bold]Install plan:[/bold]")

    pending = 0
    blocked = 0
    for step in plan.steps:
        if step.should_skip():
            console.print(f"  [dim]skip[/dim]  {step.description}  [dim](already present)[/dim]")
            continue
        missing = step.missing_prereqs()
        if missing:
            console.print(
                f"  [red]miss[/red]  {step.description}  "
                f"[dim](needs {', '.join(missing)})[/dim]"
            )
            blocked += 1
            continue
        console.print(f"  [cyan]todo[/cyan]  {step.description}")
        console.print(f"        [dim]$ {step.render()}[/dim]")
        pending += 1

    if pending == 0 and blocked == 0:
        console.print()
        console.print("[bold green]All dependencies already present.[/bold green]")
        return
    if pending == 0 and blocked > 0:
        console.print()
        console.print(
            "[yellow]Install blocked: one or more steps are missing prerequisites.[/yellow]"
        )
        return

    if no_install:
        console.print()
        console.print(
            f"[dim]--no-install given; skipping. Run `gym-anything doctor` without it to install.[/dim]"
        )
        return

    console.print()
    try:
        reply = input(f"Run the {pending} pending step(s)? [y/N] ").strip().lower()
    except (KeyboardInterrupt, EOFError):
        console.print()
        console.print("[dim]Cancelled.[/dim]")
        return
    if reply not in {"y", "yes"}:
        console.print("[dim]Skipped.[/dim]")
        return

    console.print()
    ok = run_install_plan(plan)
    console.print()
    if ok:
        console.print("[bold green]Install complete.[/bold green] Re-run `gym-anything doctor` to verify.")
    else:
        console.print("[bold red]Install failed.[/bold red] See output above, then re-run `gym-anything doctor`.")


def main(argv=None):
    # Intercept bare invocation / --help to show rich help
    if argv is None:
        argv = sys.argv[1:]
    if not argv or argv == ["--help"] or argv == ["-h"]:
        _show_rich_help()
        return 0

    parser = argparse.ArgumentParser(prog="gym-anything", add_help=False)
    parser.add_argument("-h", "--help", action="store_true", default=False)
    sub = parser.add_subparsers(dest="cmd")

    p_verify = sub.add_parser("verify", help="Run verification checks")
    verify_sub = p_verify.add_subparsers(dest="verify_cmd", required=True)

    p_verify_spec = verify_sub.add_parser("spec", help="Verify one environment and its task specs")
    p_verify_spec.add_argument("env_dir")
    p_verify_spec.add_argument("--task")
    p_verify_spec.add_argument("--json", action="store_true")
    p_verify_spec.set_defaults(func=cmd_verify_spec)

    p_verify_corpus = verify_sub.add_parser("corpus", help="Verify all environment and task specs under a root")
    p_verify_corpus.add_argument("root", nargs="?", default="benchmarks/cua_world/environments")
    p_verify_corpus.add_argument("--max-failures", type=int)
    p_verify_corpus.add_argument("--write-status-manifest")
    p_verify_corpus.add_argument("--write-verified-split")
    p_verify_corpus.add_argument("--write-missing-hook-manifest")
    p_verify_corpus.add_argument("--json", action="store_true")
    p_verify_corpus.set_defaults(func=cmd_verify_corpus)

    p_verify_task = verify_sub.add_parser("task", help="Run a task through reset/finalize and execute its verifier")
    p_verify_task.add_argument("env_dir")
    p_verify_task.add_argument("--task", required=True)
    p_verify_task.add_argument("--seed", type=int, default=42)
    p_verify_task.add_argument("--use_cache", action="store_true")
    p_verify_task.add_argument("--cache_level", default="pre_start")
    p_verify_task.add_argument("--use_savevm", action="store_true")
    p_verify_task.add_argument("--json", action="store_true")
    p_verify_task.set_defaults(func=cmd_verify_task)

    p_val = sub.add_parser("validate", help="Validate env/task specs")
    p_val.add_argument("env_dir")
    p_val.add_argument("--task")
    p_val.set_defaults(func=cmd_validate)

    p_list = sub.add_parser("list", help="List available environments")
    p_list.add_argument("-v", "--verbose", action="store_true", help="Show tasks for each environment")
    p_list.set_defaults(func=cmd_list)

    p_run = sub.add_parser("run", help="Run an environment")
    p_run.add_argument("env_dir", help="Environment name (e.g. moodle_env) or path")
    p_run.add_argument("--task", help="Task ID to load")
    p_run.add_argument("--interactive", "-i", action="store_true",
                       help="Keep environment alive for interactive use (VNC/SSH). Press Ctrl+C to stop.")
    p_run.add_argument("--steps", type=int, help="Number of steps to run (non-interactive mode)")
    p_run.add_argument("--seed", type=int, default=42)
    p_run.add_argument("--debug", action="store_true")
    p_run.add_argument("--open-vnc", action="store_true",
                       help="Automatically open VNC viewer after boot (macOS: Screen Sharing)")
    p_run.set_defaults(func=cmd_run)

    p_compat = sub.add_parser("compatibility", help="Show the runner compatibility checklist")
    p_compat.add_argument("--runner", choices=["docker", "qemu", "qemu_native", "avd", "avd_native", "avf", "apptainer", "local"])
    p_compat.add_argument("--json", action="store_true")
    p_compat.set_defaults(func=cmd_compatibility)

    p_bench = sub.add_parser("benchmark", help="Run agent evaluation on benchmark tasks")
    p_bench.add_argument("env_dir", help="Environment name (e.g. zotero) or 'all' for full corpus")
    p_bench.add_argument("--task", help="Task ID. Omit to run all tasks in the split (batch mode)")
    p_bench.add_argument("--agent", required=True, help="Agent class name (e.g. ClaudeAgent)")
    p_bench.add_argument("--model", help="Model identifier (e.g. claude-opus-4)")
    p_bench.add_argument("--exp-name", help="Experiment name for output directory")
    p_bench.add_argument("--steps", type=int, help="Max steps per task (overrides task.json; falls back to task.json, then 50)")
    p_bench.add_argument("--seed", type=int, default=42)
    p_bench.add_argument("--temperature", type=float, help="Sampling temperature")
    p_bench.add_argument("--split", default="test", help="Task split for batch mode (default: test)")
    p_bench.add_argument("--surface", choices=("raw", "verified"), default="raw")
    p_bench.add_argument("--use-cache", action="store_true")
    p_bench.add_argument("--cache-level", default="pre_start")
    p_bench.add_argument("--use-savevm", action="store_true")
    p_bench.add_argument("--verbose", action="store_true")
    p_bench.add_argument("--debug", action="store_true")
    p_bench.add_argument("--agent-arg", action="append", metavar="KEY=VALUE",
                         help="Extra agent argument (repeatable, e.g. --agent-arg history_n=4)")
    p_bench.set_defaults(func=cmd_benchmark)

    p_agents = sub.add_parser("agents", help="List available agent implementations")
    p_agents.set_defaults(func=cmd_agents)

    p_cache = sub.add_parser("cache", help="Manage the gym-anything cache directory")
    cache_sub = p_cache.add_subparsers(dest="cache_cmd", required=True)

    p_cache_list = cache_sub.add_parser("list", help="Show cache contents and sizes")
    p_cache_list.set_defaults(func=cmd_cache_list)

    p_cache_purge = cache_sub.add_parser("purge", help="Delete cached files to free disk space")
    p_cache_purge.add_argument("component", nargs="?",
                               help="Component name (e.g. qemu-work) or category ('work', 'base'). "
                                    "Default: purge work only.")
    p_cache_purge.add_argument("--all", action="store_true",
                               help="Purge everything including base images")
    p_cache_purge.add_argument("-y", "--yes", action="store_true",
                               help="Skip confirmation prompt")
    p_cache_purge.set_defaults(func=cmd_cache_purge)

    p_doctor = sub.add_parser("doctor", help="Check system prerequisites and optional verifier imports")
    p_doctor.add_argument("--runner", choices=["docker", "qemu", "qemu_native", "avd", "avd_native", "avf", "apptainer", "local"])
    p_doctor.add_argument("--verification-root")
    p_doctor.add_argument("--json", action="store_true")
    p_doctor.add_argument("--no-install", action="store_true", help="Skip the interactive install prompt")
    p_doctor.set_defaults(func=cmd_doctor)

    args = parser.parse_args(argv)

    # If top-level --help slipped through (e.g. "gym-anything -h")
    if getattr(args, "help", False) and not args.cmd:
        _show_rich_help()
        return 0

    if not args.cmd:
        _show_rich_help()
        return 0

    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
