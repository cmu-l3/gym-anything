"use client";

import { api, SoftwareEntry, TaskSummary } from "@/lib/api";
import { useStore } from "@/lib/store";
import { useQuery } from "@tanstack/react-query";
import * as Popover from "@radix-ui/react-popover";
import { Check, ChevronDown, Plus, Search, Sparkles, X } from "lucide-react";
import { useMemo, useState } from "react";
import { cn } from "@/lib/cn";

export function SoftwarePicker() {
  const selection = useStore((s) => s.selection);
  const setSelection = useStore((s) => s.setSelection);
  const clear = useStore((s) => s.clearSelection);
  const [open, setOpen] = useState(false);

  const label = useMemo(() => {
    if (!selection.envDir) return "software: all";
    if (selection.isNewTask) return `${selection.envDir} · new task`;
    if (selection.taskId) return `${selection.envDir} / ${selection.taskId}`;
    return selection.envDir;
  }, [selection]);

  return (
    <div className="inline-flex items-center">
      <Popover.Root open={open} onOpenChange={setOpen}>
        <Popover.Trigger asChild>
          <button
            type="button"
            className="chip border-purple/40 text-purple bg-purple-soft hover:bg-purple/15 transition-colors"
          >
            <Sparkles size={12} />
            <span>{label}</span>
            <ChevronDown size={12} />
          </button>
        </Popover.Trigger>
        <Popover.Portal>
          <Popover.Content
            sideOffset={6}
            align="end"
            side="top"
            collisionPadding={12}
            className="z-50 panel shadow-elevated overflow-hidden w-[min(640px,calc(100vw-2rem))] data-[state=open]:animate-in"
          >
            <PickerPanel
              onClose={() => setOpen(false)}
              onPickEnv={(env) => {
                setSelection({ envDir: env, taskId: null, isNewTask: false });
              }}
              onPickTask={(env, task) => {
                setSelection({ envDir: env, taskId: task, isNewTask: false });
                setOpen(false);
              }}
              onNewTask={(env) => {
                setSelection({ envDir: env, taskId: null, isNewTask: true });
                setOpen(false);
              }}
              onSkip={() => {
                setSelection({ taskId: null, isNewTask: false });
                setOpen(false);
              }}
              onUseEnvOnly={(env) => {
                setSelection({ envDir: env, taskId: null, isNewTask: false });
                setOpen(false);
              }}
              currentEnv={selection.envDir}
            />
          </Popover.Content>
        </Popover.Portal>
      </Popover.Root>
      {selection.envDir && (
        <button
          aria-label="Clear selection"
          onClick={clear}
          className="ml-1 inline-flex items-center justify-center h-5 w-5 rounded-md text-fg/50 hover:text-fg hover:bg-elevated"
        >
          <X size={12} />
        </button>
      )}
    </div>
  );
}

function PickerPanel({
  onClose,
  onPickEnv,
  onPickTask,
  onNewTask,
  onSkip,
  onUseEnvOnly,
  currentEnv,
}: {
  onClose: () => void;
  onPickEnv: (env: string) => void;
  onPickTask: (env: string, task: string) => void;
  onNewTask: (env: string) => void;
  onSkip: () => void;
  onUseEnvOnly: (env: string) => void;
  currentEnv: string | null;
}) {
  const [search, setSearch] = useState("");
  const [hoveredEnv, setHoveredEnv] = useState<string | null>(currentEnv);

  const software = useQuery({
    queryKey: ["software"],
    queryFn: () => api.listSoftware(),
  });

  const tasks = useQuery({
    queryKey: ["tasks", hoveredEnv],
    queryFn: () => api.listTasks(hoveredEnv!),
    enabled: !!hoveredEnv,
  });

  const filteredEnvs = useMemo(() => {
    const items = software.data?.items ?? [];
    const q = search.trim().toLowerCase();
    if (!q) return items;
    return items.filter(
      (s) =>
        s.env_dir.includes(q) ||
        (s.description ?? "").toLowerCase().includes(q) ||
        s.tags.some((t) => t.toLowerCase().includes(q)),
    );
  }, [software.data, search]);

  return (
    <div style={{ maxHeight: "min(60vh, 480px)" }} className="flex flex-col">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-border">
        <Search size={14} className="text-muted" />
        <input
          autoFocus
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search software, tags, descriptions…"
          className="flex-1 bg-transparent text-sm focus:outline-none placeholder:text-muted/70"
        />
        <button
          onClick={onSkip}
          className="text-xs text-muted hover:text-fg whitespace-nowrap"
        >
          skip · general
        </button>
      </div>
      <div className="grid grid-cols-2 divide-x divide-border flex-1 min-h-0">
        <EnvList
          items={filteredEnvs}
          loading={software.isLoading}
          hoveredEnv={hoveredEnv}
          currentEnv={currentEnv}
          onHover={setHoveredEnv}
          onPick={onPickEnv}
          onUseEnvOnly={onUseEnvOnly}
        />
        <TaskList
          envDir={hoveredEnv}
          tasks={tasks.data?.items ?? []}
          loading={tasks.isLoading}
          onPick={(t) => onPickTask(hoveredEnv!, t)}
          onNewTask={() => hoveredEnv && onNewTask(hoveredEnv)}
          onUseEnvOnly={() => hoveredEnv && onUseEnvOnly(hoveredEnv)}
        />
      </div>
    </div>
  );
}

function EnvList({
  items,
  loading,
  hoveredEnv,
  currentEnv,
  onHover,
  onPick,
  onUseEnvOnly,
}: {
  items: SoftwareEntry[];
  loading: boolean;
  hoveredEnv: string | null;
  currentEnv: string | null;
  onHover: (env: string) => void;
  onPick: (env: string) => void;
  onUseEnvOnly: (env: string) => void;
}) {
  return (
    <ul
      className="overflow-y-auto py-1 text-sm"
      role="listbox"
    >
      {loading && <li className="px-3 py-2 text-muted">Loading…</li>}
      {!loading && items.length === 0 && (
        <li className="px-3 py-2 text-muted">No matches.</li>
      )}
      {items.map((s) => (
        <li key={s.env_dir}>
          <button
            type="button"
            onMouseEnter={() => onHover(s.env_dir)}
            onClick={() => onPick(s.env_dir)}
            onDoubleClick={() => onUseEnvOnly(s.env_dir)}
            className={cn(
              "w-full text-left px-3 py-2 flex items-center gap-2",
              hoveredEnv === s.env_dir ? "bg-elevated" : "hover:bg-elevated/60",
              currentEnv === s.env_dir && "text-accent",
            )}
          >
            <div className="flex-1 min-w-0">
              <div className="truncate">{s.env_dir}</div>
              <div className="text-[11px] text-muted truncate">
                {s.description ?? "—"}
              </div>
            </div>
            <span className="text-[10px] text-muted tabular-nums">
              {s.task_count}
            </span>
            {currentEnv === s.env_dir && <Check size={13} className="text-accent" />}
          </button>
        </li>
      ))}
    </ul>
  );
}

function TaskList({
  envDir,
  tasks,
  loading,
  onPick,
  onNewTask,
  onUseEnvOnly,
}: {
  envDir: string | null;
  tasks: TaskSummary[];
  loading: boolean;
  onPick: (task: string) => void;
  onNewTask: () => void;
  onUseEnvOnly: () => void;
}) {
  if (!envDir) {
    return (
      <div className="px-3 py-4 text-sm text-muted flex items-center">
        Hover a software on the left to see its tasks.
      </div>
    );
  }
  return (
    <div className="flex flex-col min-h-0">
      <div className="px-3 py-2 text-[11px] uppercase tracking-wider text-muted flex items-center justify-between border-b border-border gap-2">
        <span className="truncate">{envDir} · tasks</span>
        <div className="flex items-center gap-2">
          <button
            onClick={onUseEnvOnly}
            className="inline-flex items-center gap-1 text-accent hover:underline normal-case tracking-normal text-xs"
          >
            <Check size={11} />
            use env
          </button>
          <button
            onClick={onNewTask}
            className="inline-flex items-center gap-1 text-accent hover:underline normal-case tracking-normal text-xs"
          >
            <Plus size={11} />
            new task
          </button>
        </div>
      </div>
      <ul className="overflow-y-auto py-1 text-sm flex-1 min-h-0">
        {loading && <li className="px-3 py-2 text-muted">Loading tasks…</li>}
        {!loading && tasks.length === 0 && (
          <li className="px-3 py-2 text-muted">No tasks defined.</li>
        )}
        {tasks.map((t) => (
          <li key={t.task_id}>
            <button
              type="button"
              onClick={() => onPick(t.task_id)}
              className="w-full text-left px-3 py-2 hover:bg-elevated"
            >
              <div className="truncate">{t.task_id}</div>
              <div className="text-[11px] text-muted line-clamp-2 leading-snug">
                {t.description ?? "—"}
              </div>
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
