"use client";

import { useStore } from "@/lib/store";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api, VNCStatus } from "@/lib/api";
import { Loader2, MonitorPlay, Power, RefreshCcw, Square } from "lucide-react";
import { useEffect, useRef } from "react";
import { Empty } from "@/components/ui/Empty";
import { cn } from "@/lib/cn";

export function VNCStage() {
  const selection = useStore((s) => s.selection);
  const qc = useQueryClient();
  const status = useQuery({
    queryKey: ["vnc"],
    queryFn: () => api.vncStatus(),
    refetchInterval: (q) => {
      const data = q.state.data as VNCStatus | undefined;
      if (!data?.active) return false;
      return data.status === "running" ? false : 1500;
    },
  });

  const start = useMutation({
    mutationFn: () => api.vncStart(selection.envDir!),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["vnc"] }),
  });

  const reset = useMutation({
    mutationFn: () =>
      api.vncReset((status.data as Extract<VNCStatus, { active: true }>).id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["vnc"] }),
  });

  const stop = useMutation({
    mutationFn: () =>
      api.vncStop((status.data as Extract<VNCStatus, { active: true }>).id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["vnc"] }),
  });

  if (!selection.envDir) {
    return (
      <div className="h-full flex">
        <Empty
          icon={<MonitorPlay size={32} />}
          title="No env selected"
          hint="Pick a software using the chip below to enable VNC."
          className="m-auto"
        />
      </div>
    );
  }

  const active = status.data?.active
    ? (status.data as Extract<VNCStatus, { active: true }>)
    : null;
  // Backend statuses are: starting | running | failed | stopping | stopped.
  // Only "running" means the proxy can connect; "starting" needs a spinner;
  // "failed" surfaces the upstream error inline.
  const isStarting = active?.status === "starting";
  const isFailed = active?.status === "failed";
  const isRunning = active?.status === "running";

  return (
    <div className="h-full flex flex-col">
      <header className="flex items-center gap-2 px-3 py-2 border-b border-border bg-elevated/40">
        <div className="text-xs uppercase tracking-wider text-muted font-display">
          VNC ·
        </div>
        <div className="text-sm text-fg/90 font-mono">
          {active
            ? `${active.env_dir}${isRunning ? ` · :${active.vnc_port}` : ""}`
            : selection.envDir}
        </div>
        {isStarting && (
          <span className="chip border-accent/40 text-accent bg-accent-soft">
            <Loader2 size={11} className="animate-spin" />
            booting
          </span>
        )}
        {isFailed && (
          <span className="chip border-danger/40 text-danger bg-danger/10">
            failed
          </span>
        )}
        <div className="ml-auto flex items-center gap-1">
          <button
            disabled={!isRunning || reset.isPending}
            onClick={() => reset.mutate()}
            className="btn-ghost"
          >
            <RefreshCcw size={13} />
            Reset
          </button>
          {active ? (
            <button
              disabled={stop.isPending}
              onClick={() => stop.mutate()}
              className="btn-outline"
            >
              <Square size={13} />
              Stop
            </button>
          ) : (
            <button
              disabled={start.isPending}
              onClick={() => start.mutate()}
              className="btn-primary"
            >
              <Power size={13} />
              {start.isPending ? "Starting…" : "Start"}
            </button>
          )}
        </div>
      </header>
      <div className="flex-1 min-h-0">
        {isRunning && active ? (
          <VNCFrame session={active} />
        ) : (
          <div className="h-full flex items-center justify-center px-6">
            {start.isError ? (
              <div className="text-sm text-danger max-w-md text-center">
                {(start.error as Error).message}
              </div>
            ) : isFailed && active ? (
              <div className="text-sm text-danger max-w-md text-center space-y-2">
                <div className="font-medium">Env failed to boot.</div>
                <div className="text-fg/70 text-xs leading-relaxed">
                  {active.last_error ?? "no error message available"}
                </div>
              </div>
            ) : isStarting || start.isPending ? (
              <div className="flex flex-col items-center gap-2 text-muted text-sm">
                <Loader2 size={20} className="animate-spin text-accent" />
                <div>Booting environment — this can take a few minutes.</div>
                <div className="text-[11px] text-muted/70">
                  pre_start and post_start hooks are running
                </div>
              </div>
            ) : (
              <Empty
                icon={<MonitorPlay size={28} />}
                title="VNC is not running"
                hint="Press Start to boot the environment and stream the desktop into this panel."
              />
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function VNCFrame({
  session,
}: {
  session: Extract<VNCStatus, { active: true }>;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const sessionId = session.id;
  useEffect(() => {
    let cancelled = false;
    let rfb: any | null = null;
    let cleanup: (() => void) | null = null;
    (async () => {
      const RFB = (await import("@novnc/novnc")).default;
      if (cancelled || !ref.current) return;
      const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
      const url = `${proto}//${window.location.host}/api/vnc/ws/${sessionId}`;
      rfb = new RFB(ref.current, url, {
        credentials: session.vnc_password
          ? { password: session.vnc_password }
          : undefined,
        wsProtocols: ["binary"],
      });
      rfb.viewOnly = false;
      rfb.scaleViewport = true;
      rfb.resizeSession = false;
      rfb.background = "#0a0a0a";
      cleanup = () => {
        try {
          rfb?.disconnect();
        } catch {
          /* ignore */
        }
      };
    })();
    return () => {
      cancelled = true;
      cleanup?.();
    };
  }, [sessionId, session.vnc_password]);
  return <div ref={ref} className={cn("w-full h-full bg-bg")} />;
}
