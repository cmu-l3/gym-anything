"use client";

import { api, ChangesSummaryResp } from "@/lib/api";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AlertTriangle,
  CheckCircle2,
  HelpCircle,
  Loader2,
  RefreshCw,
  Sparkles,
  XCircle,
} from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/cn";

/**
 * Inline "Changes Summary" block. Rendered in two places:
 *  - inside the live RunMonitor for the run the user just dispatched
 *  - inside the InteractionHistory timeline for any past finished run
 *
 * Click "Summarize changes" → server calls GPT-5.4 over the env diff +
 * the originating feedback message and returns a verdict, paragraph,
 * and bullets. Cached server-side by (run_id, diff signature, model,
 * effort).
 */
export function ChangesSummary({
  runId,
  variant = "block",
}: {
  runId: string;
  variant?: "block" | "inline";
}) {
  const [enabled, setEnabled] = useState(false);
  const qc = useQueryClient();
  const summary = useQuery<ChangesSummaryResp>({
    queryKey: ["changes-summary", runId],
    queryFn: () => api.changesSummary(runId),
    enabled,
    retry: false,
  });

  const refresh = useMutation({
    mutationFn: () => api.changesSummary(runId, true),
    onSuccess: (data) => qc.setQueryData(["changes-summary", runId], data),
  });

  const wrapperCls =
    variant === "inline"
      ? "mt-2 border-t border-border pt-2"
      : "border-t border-border bg-elevated/30";

  return (
    <section className={wrapperCls}>
      <header
        className={cn(
          "flex items-center gap-2",
          variant === "inline" ? "py-1" : "px-3 py-2",
        )}
      >
        <Sparkles size={12} className="text-accent" />
        <div className="text-[12px] font-medium">Changes Summary</div>
        {variant === "block" && (
          <span className="text-[11px] text-muted">
            plain-English diff over the env folder, judged against the
            originating feedback
          </span>
        )}
        <div className="ml-auto flex items-center gap-1">
          {enabled && summary.data && (
            <button
              onClick={() => refresh.mutate()}
              disabled={refresh.isPending}
              className="btn-ghost text-xs"
            >
              <RefreshCw size={11} />
              Refresh
            </button>
          )}
          {!enabled && (
            <button
              onClick={() => setEnabled(true)}
              className={cn(
                variant === "inline" ? "btn-outline" : "btn-primary",
                "text-xs",
              )}
            >
              <Sparkles size={11} />
              Summarize changes
            </button>
          )}
        </div>
      </header>
      {enabled && (
        <div className={variant === "inline" ? "" : "px-3 pb-3"}>
          {summary.isLoading || refresh.isPending ? (
            <div className="flex items-center gap-2 text-xs text-muted py-3">
              <Loader2 size={12} className="animate-spin" />
              Asking the model to read the diff…
            </div>
          ) : summary.isError ? (
            <div className="text-xs text-danger py-3">
              {(summary.error as Error).message}
            </div>
          ) : summary.data ? (
            <ChangesSummaryBody data={summary.data} />
          ) : null}
        </div>
      )}
    </section>
  );
}

function ChangesSummaryBody({ data }: { data: ChangesSummaryResp }) {
  const verdictColour = {
    yes: "border-success/40 text-success bg-success/10",
    partial: "border-warn/40 text-warn bg-warn/10",
    no: "border-danger/40 text-danger bg-danger/10",
    unclear: "border-muted/40 text-muted bg-elevated",
  } as const;
  const verdictIcon = {
    yes: <CheckCircle2 size={12} />,
    partial: <AlertTriangle size={12} />,
    no: <XCircle size={12} />,
    unclear: <HelpCircle size={12} />,
  } as const;
  return (
    <div className="space-y-3 text-[12.5px] leading-relaxed">
      <div className="flex items-center gap-2 text-[11px] text-muted flex-wrap">
        <span className={cn("chip", verdictColour[data.addressed_feedback])}>
          {verdictIcon[data.addressed_feedback]}
          addressed: {data.addressed_feedback}
        </span>
        <span className="chip">
          {data.file_count} file{data.file_count === 1 ? "" : "s"}
        </span>
        <span className="chip">
          <span className="text-success">+{data.additions}</span>{" "}
          <span className="text-danger">-{data.deletions}</span>
        </span>
        {data.cached && <span className="chip">cached</span>}
        <span className="text-muted">
          {data.model} · {data.reasoning_effort}
        </span>
      </div>
      <p className="text-fg/90">{data.summary}</p>
      <p className="text-fg/75 italic text-[11.5px]">
        <span className="text-muted not-italic">Verdict reasoning:</span>{" "}
        {data.addressed_reason || "—"}
      </p>
      {data.bullets.length > 0 && (
        <ul className="space-y-1.5">
          {data.bullets.map((b, i) => (
            <li key={i} className="flex items-start gap-2">
              <span className="mt-1.5 h-1 w-1 rounded-full bg-accent shrink-0" />
              <span className="text-fg/85">{b}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
