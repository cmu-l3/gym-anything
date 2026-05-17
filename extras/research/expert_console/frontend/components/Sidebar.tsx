"use client";

import { cn } from "@/lib/cn";
import { useStore } from "@/lib/store";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ChevronsLeft,
  ChevronsRight,
  Cog,
  History,
  Sparkles,
} from "lucide-react";
import { api } from "@/lib/api";
import { useState } from "react";
import { SettingsPanel } from "@/components/SettingsPanel";

const ITEMS = [
  { id: "current", label: "Current Creation", icon: Sparkles },
  { id: "past", label: "Past Creations", icon: History },
  { id: "settings", label: "Settings", icon: Cog },
] as const;

export function Sidebar() {
  const [collapsed, setCollapsed] = useState(false);
  const [active, setActive] = useState<(typeof ITEMS)[number]["id"]>("current");
  const sessionId = useStore((s) => s.sessionId);
  const setSessionId = useStore((s) => s.setSessionId);
  const setSelection = useStore((s) => s.setSelection);
  const clearSelection = useStore((s) => s.clearSelection);
  const qc = useQueryClient();

  const sessions = useQuery({
    queryKey: ["sessions"],
    queryFn: () => api.listSessions(),
  });

  // Clicking a session in the sidebar should also restore its target
  // (env_dir / task_id) into the picker, so the inspection panel,
  // VNC pane, and memory diff panel all refresh to that context.
  // Clicking the active one again clears.
  const handleSelectSession = (id: string | null) => {
    if (id === null) {
      setSessionId(null);
      clearSelection();
      return;
    }
    const next = sessions.data?.find((s) => s.id === id);
    setSessionId(id);
    if (next) {
      setSelection({
        envDir: next.env_dir,
        taskId: next.task_id,
        isNewTask: false,
      });
      // Refresh the side-panel diffs against the new env right away.
      qc.invalidateQueries({ queryKey: ["env-diff"] });
      qc.invalidateQueries({ queryKey: ["memory-diff"] });
      qc.invalidateQueries({ queryKey: ["memory"] });
    }
  };

  return (
    <aside
      className={cn(
        "shrink-0 panel rounded-none border-y-0 border-l-0 flex flex-col",
        collapsed ? "w-14" : "w-64",
        "transition-[width] duration-200 ease-out",
      )}
    >
      <div className="flex items-center justify-between px-3 py-3 border-b border-border">
        {!collapsed && (
          <div className="text-xs uppercase tracking-[0.18em] text-muted font-display">
            Expert Console
          </div>
        )}
        <button
          aria-label="Toggle sidebar"
          onClick={() => setCollapsed((v) => !v)}
          className="ml-auto h-7 w-7 inline-flex items-center justify-center rounded-md text-fg/60 hover:text-fg hover:bg-elevated"
        >
          {collapsed ? <ChevronsRight size={14} /> : <ChevronsLeft size={14} />}
        </button>
      </div>

      <nav className="px-2 py-3 space-y-1 border-b border-border">
        {ITEMS.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => setActive(id)}
            className={cn(
              "w-full text-left flex items-center gap-2 px-2.5 py-2 rounded-md text-sm transition-colors",
              active === id
                ? "bg-elevated text-fg"
                : "text-fg/70 hover:text-fg hover:bg-elevated/60",
              collapsed && "justify-center",
            )}
            aria-current={active === id ? "page" : undefined}
          >
            <Icon size={15} className="shrink-0" />
            {!collapsed && <span>{label}</span>}
          </button>
        ))}
      </nav>

      {!collapsed && (
        <div className="flex-1 overflow-y-auto px-2 py-3">
          {active !== "settings" && (
            <SessionList
              sessions={sessions.data ?? []}
              isLoading={sessions.isLoading}
              showAll={active === "past"}
              activeId={sessionId}
              onSelect={handleSelectSession}
            />
          )}
          {active === "settings" && <SettingsPanel />}
        </div>
      )}
    </aside>
  );
}

function SessionList({
  sessions,
  isLoading,
  showAll,
  activeId,
  onSelect,
}: {
  sessions: import("@/lib/api").SessionSummary[];
  isLoading: boolean;
  showAll: boolean;
  activeId: string | null;
  onSelect: (id: string | null) => void;
}) {
  const list = showAll
    ? sessions
    : sessions.slice(0, 1).filter((s) => s.status === "active");

  if (isLoading) {
    return <div className="text-xs text-muted px-2 py-2">Loading sessions…</div>;
  }
  if (list.length === 0) {
    return (
      <div className="text-xs text-muted px-2 py-2 leading-relaxed">
        {showAll ? "No sessions yet." : "Submit feedback to start a session."}
      </div>
    );
  }
  return (
    <ul className="space-y-1">
      {list.map((s) => (
        <li key={s.id}>
          <button
            onClick={() => onSelect(s.id === activeId ? null : s.id)}
            className={cn(
              "w-full text-left flex flex-col gap-0.5 px-2.5 py-2 rounded-md text-sm transition-colors",
              s.id === activeId
                ? "bg-accent-soft text-fg ring-1 ring-accent/30"
                : "text-fg/80 hover:bg-elevated",
            )}
          >
            <span className="truncate font-medium">{s.title}</span>
            <span className="text-[11px] text-muted">
              {s.env_dir ?? "general"} · {s.run_count} run{s.run_count === 1 ? "" : "s"}
            </span>
          </button>
        </li>
      ))}
    </ul>
  );
}

