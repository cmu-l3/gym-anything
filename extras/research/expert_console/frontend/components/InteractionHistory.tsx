"use client";

import { api } from "@/lib/api";
import { useStore } from "@/lib/store";
import { useQuery } from "@tanstack/react-query";
import {
  CheckCircle2,
  Circle,
  Loader2,
  MessageSquare,
  Pause,
  ScrollText,
  Square,
  XCircle,
} from "lucide-react";
import { useMemo } from "react";
import { Empty } from "@/components/ui/Empty";
import { cn } from "@/lib/cn";
import { ChangesSummary } from "@/components/ChangesSummary";

export function InteractionHistory() {
  const sessionId = useStore((s) => s.sessionId);
  const selection = useStore((s) => s.selection);

  // 1) Always fetch the global session list so we can find a fallback
  //    session matching the currently-picked env when no sessionId is
  //    explicitly set.
  const allSessions = useQuery({
    queryKey: ["sessions"],
    queryFn: () => api.listSessions(),
    refetchInterval: 5_000,
  });

  // 2) If no sessionId, fall back to the most recent active session for
  //    the picked env (if any).
  const fallbackId: string | null = useMemo(() => {
    if (sessionId) return null;
    if (!selection.envDir) return null;
    const sessions = allSessions.data ?? [];
    const match = sessions.find(
      (s) =>
        s.env_dir === selection.envDir &&
        (!selection.taskId || s.task_id === selection.taskId),
    );
    return match?.id ?? null;
  }, [allSessions.data, selection.envDir, selection.taskId, sessionId]);

  const effectiveId = sessionId ?? fallbackId;

  // 3) Load that session's detail (feedbacks + runs).
  const sessionDetail = useQuery({
    queryKey: ["session", effectiveId],
    queryFn: () => api.getSession(effectiveId!),
    enabled: !!effectiveId,
    refetchInterval: 5_000,
  });

  const data = sessionDetail.data;

  if (!data) {
    return (
      <div className="h-full flex">
        <Empty
          icon={<ScrollText size={28} />}
          title="No interaction history"
          hint="Submit a feedback below to start a session. Past nudges and pipeline runs show up here in order."
          className="m-auto"
        />
      </div>
    );
  }

  const timeline = [
    ...data.feedbacks.map((f) => ({
      kind: "feedback" as const,
      ts: f.created_at,
      item: f,
    })),
    ...data.runs.map((r) => ({
      kind: "run" as const,
      ts: r.created_at,
      item: r,
    })),
  ].sort((a, b) => a.ts.localeCompare(b.ts));

  return (
    <div className="h-full overflow-y-auto px-4 py-4">
      <header className="mb-4">
        <h2 className="heading text-lg">{data.title}</h2>
        <div className="flex flex-wrap gap-1.5 mt-2 text-xs text-muted">
          <span className="chip">{data.status}</span>
          {data.env_dir && <span className="chip">{data.env_dir}</span>}
          {data.task_id && <span className="chip">{data.task_id}</span>}
          <span className="chip">{data.feedback_count} feedback</span>
          <span className="chip">{data.run_count} runs</span>
        </div>
      </header>
      <ol className="relative pl-5 space-y-4 border-l border-border">
        {timeline.map((entry, i) => (
          <li key={`${entry.kind}-${i}`} className="relative">
            <span
              className={cn(
                "absolute -left-[10px] top-1.5 h-4 w-4 rounded-full border-2 border-border bg-surface flex items-center justify-center",
                entry.kind === "feedback" ? "text-purple" : "text-accent",
              )}
            >
              {entry.kind === "feedback" ? (
                <MessageSquare size={9} />
              ) : (
                <RunIcon status={(entry.item as any).status} />
              )}
            </span>
            {entry.kind === "feedback" ? (
              <FeedbackEntry feedback={entry.item} />
            ) : (
              <RunEntry run={entry.item} />
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}

function FeedbackEntry({
  feedback,
}: {
  feedback: import("@/lib/api").FeedbackRecord;
}) {
  return (
    <div className="panel p-3 space-y-2">
      <div className="flex items-center gap-2 text-[11px] text-muted">
        <span className="chip-purple">to: {feedback.route}</span>
        <span className="chip">memory: {feedback.memory_tier}</span>
        {feedback.suggest_checklist_change && (
          <span className="chip-accent">checklist amendment</span>
        )}
        {feedback.is_new_task && <span className="chip-accent">new task</span>}
        <span className="ml-auto">{new Date(feedback.created_at).toLocaleString()}</span>
      </div>
      <p className="text-sm text-fg/90 leading-relaxed whitespace-pre-wrap">
        {feedback.message}
      </p>
      {feedback.appended_to_path && (
        <div className="text-[11px] text-muted font-mono truncate">
          appended → {feedback.appended_to_path}
        </div>
      )}
    </div>
  );
}

function RunEntry({ run }: { run: import("@/lib/api").RunSummary }) {
  // Only finished/failed runs are worth summarizing — running runs have
  // no diff yet, and stopped runs were aborted by the user (the env
  // folder probably wasn't touched).
  const canSummarize = run.status === "finished" || run.status === "failed";
  return (
    <div className="panel p-3 space-y-1">
      <div className="flex items-center gap-2 text-[11px] text-muted">
        <span className="chip-accent">{run.pipeline}</span>
        <span className={cn("chip", statusClass(run.status))}>
          {run.status}
        </span>
        {run.current_phase && <span className="chip">{run.current_phase}</span>}
        <span className="ml-auto">{new Date(run.created_at).toLocaleString()}</span>
      </div>
      <div className="text-[11px] text-muted font-mono truncate">
        run · {run.id}
      </div>
      {run.exit_code !== null && (
        <div className="text-[11px] text-muted">exit: {run.exit_code}</div>
      )}
      {canSummarize && <ChangesSummary runId={run.id} variant="inline" />}
    </div>
  );
}

function statusClass(status: string) {
  switch (status) {
    case "running":
      return "border-accent/40 text-accent bg-accent-soft";
    case "finished":
      return "border-success/40 text-success bg-success/10";
    case "failed":
      return "border-danger/40 text-danger bg-danger/10";
    case "stopped":
      return "border-warn/40 text-warn bg-warn/10";
    default:
      return "";
  }
}

function RunIcon({ status }: { status: string }) {
  switch (status) {
    case "running":
      return <Loader2 size={9} className="animate-spin" />;
    case "finished":
      return <CheckCircle2 size={9} className="text-success" />;
    case "failed":
      return <XCircle size={9} className="text-danger" />;
    case "stopped":
      return <Square size={9} className="text-warn" />;
    default:
      return <Circle size={9} />;
  }
}
