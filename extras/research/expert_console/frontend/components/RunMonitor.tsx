"use client";

import { api } from "@/lib/api";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, Loader2, Square, XCircle } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/cn";
import { ChangesSummary } from "@/components/ChangesSummary";

type LogLine = { seq: number; stream: string; line: string; ts: string };

type Status = "pending" | "running" | "finished" | "failed" | "stopped";

export function RunMonitor({
  runId,
  onClose,
}: {
  runId: string;
  onClose: () => void;
}) {
  const [logs, setLogs] = useState<LogLine[]>([]);
  const [status, setStatus] = useState<Status>("running");
  const [phase, setPhase] = useState<string | null>(null);
  const [exitCode, setExitCode] = useState<number | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const qc = useQueryClient();

  useEffect(() => {
    const es = new EventSource(`/api/runs/${encodeURIComponent(runId)}/stream`);
    es.addEventListener("log", (ev: MessageEvent) => {
      const data = JSON.parse(ev.data) as LogLine;
      setLogs((prev) => [...prev, data]);
    });
    es.addEventListener("status", (ev: MessageEvent) => {
      const data = JSON.parse(ev.data) as {
        status: Status;
        exit_code: number | null;
        current_phase: string | null;
      };
      setStatus(data.status);
      setPhase(data.current_phase);
      setExitCode(data.exit_code);
      if (
        data.status === "finished" ||
        data.status === "failed" ||
        data.status === "stopped"
      ) {
        es.close();
        qc.invalidateQueries({ queryKey: ["memory-diff"] });
        qc.invalidateQueries({ queryKey: ["session"] });
        qc.invalidateQueries({ queryKey: ["sessions"] });
      }
    });
    es.onerror = () => {
      // Stream closed (probably terminal). Don't reconnect aggressively.
    };
    return () => es.close();
  }, [runId, qc]);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs.length]);

  const stop = useMutation({
    mutationFn: () => api.stopRun(runId),
  });

  const isTerminal = status === "finished" || status === "failed" || status === "stopped";

  return (
    <section className="panel overflow-hidden flex flex-col">
      <header className="flex items-center gap-2 px-3 py-2 border-b border-border bg-elevated/50">
        <StatusBadge status={status} />
        <div className="text-xs text-muted">
          {phase ? <>phase: <span className="text-fg font-mono">{phase}</span></> : "in progress"}
        </div>
        <div className="ml-auto flex items-center gap-2">
          {!isTerminal && (
            <button
              onClick={() => stop.mutate()}
              disabled={stop.isPending}
              className="btn-outline text-xs"
            >
              <Square size={11} />
              Stop
            </button>
          )}
          {isTerminal && (
            <button onClick={onClose} className="btn-ghost text-xs">
              Close
            </button>
          )}
        </div>
      </header>
      <div
        ref={scrollRef}
        className="bg-bg max-h-60 overflow-y-auto font-mono text-[12px] leading-relaxed p-3"
      >
        {logs.length === 0 && (
          <div className="text-muted">Waiting for pipeline output…</div>
        )}
        {logs.map((line) => (
          <div
            key={line.seq}
            className={cn(
              line.stream === "stderr" && "text-danger",
              line.stream === "event" && "text-warn",
            )}
          >
            <span className="text-muted mr-2">
              {String(line.seq).padStart(4, "0")}
            </span>
            {line.line}
          </div>
        ))}
      </div>
      <footer className="px-3 py-1.5 text-[11px] text-muted border-t border-border bg-elevated/40">
        {isTerminal ? (
          <span>
            {status} · exit: {exitCode ?? "—"} · {logs.length} lines
          </span>
        ) : (
          <span>this will take time — agents work as long as they need</span>
        )}
      </footer>
      {isTerminal && status !== "stopped" && (
        <ChangesSummary runId={runId} variant="block" />
      )}
    </section>
  );
}

function StatusBadge({ status }: { status: Status }) {
  const map: Record<Status, { label: string; icon: React.ReactNode; cls: string }> = {
    pending: { label: "pending", icon: <Loader2 size={11} className="animate-spin" />, cls: "" },
    running: {
      label: "running",
      icon: <Loader2 size={11} className="animate-spin" />,
      cls: "border-accent/40 text-accent bg-accent-soft",
    },
    finished: {
      label: "finished",
      icon: <CheckCircle2 size={11} />,
      cls: "border-success/40 text-success bg-success/10",
    },
    failed: {
      label: "failed",
      icon: <XCircle size={11} />,
      cls: "border-danger/40 text-danger bg-danger/10",
    },
    stopped: {
      label: "stopped",
      icon: <Square size={11} />,
      cls: "border-warn/40 text-warn bg-warn/10",
    },
  };
  const it = map[status];
  return (
    <span className={cn("chip", it.cls)}>
      {it.icon}
      {it.label}
    </span>
  );
}
