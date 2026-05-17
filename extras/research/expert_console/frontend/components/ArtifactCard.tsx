"use client";

import { Artifact, api } from "@/lib/api";
import { useMutation, useQuery } from "@tanstack/react-query";
import { Code2, Eye, Loader2, RefreshCw, Sparkles } from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/cn";

function humanSize(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

const KIND_BADGE: Record<string, string> = {
  shell: "bg-amber-500/15 text-amber-300 border-amber-500/30",
  python: "bg-cyan-500/15 text-cyan-300 border-cyan-500/30",
  json: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  yaml: "bg-emerald-500/15 text-emerald-300 border-emerald-500/30",
  markdown: "bg-purple-500/15 text-purple-300 border-purple-500/30",
  image: "bg-pink-500/15 text-pink-300 border-pink-500/30",
  data: "bg-blue-500/15 text-blue-300 border-blue-500/30",
  other: "bg-zinc-500/15 text-zinc-300 border-zinc-500/30",
};

const _UNSUMMARIZABLE_KINDS = new Set(["image"]);

export function ArtifactCard({
  artifact,
  disableSummary = false,
}: {
  artifact: Artifact;
  disableSummary?: boolean;
}) {
  // Image / binary kinds can't usefully go through the text summarizer.
  const summarizable =
    !disableSummary && !_UNSUMMARIZABLE_KINDS.has(artifact.kind);
  const [view, setView] = useState<"summary" | "raw">(
    summarizable ? "summary" : "raw",
  );
  return (
    <div className="panel overflow-hidden flex flex-col">
      <header className="flex items-center gap-2 px-3 py-2 border-b border-border">
        <div className="min-w-0 flex-1">
          <div className="text-sm font-medium text-fg truncate">{artifact.name}</div>
          <div className="text-[11px] text-muted truncate font-mono">
            {artifact.rel_path}
          </div>
        </div>
        <span
          className={cn(
            "text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded border",
            KIND_BADGE[artifact.kind] ?? KIND_BADGE.other,
          )}
        >
          {artifact.kind}
        </span>
        <span className="text-[11px] text-muted tabular-nums">
          {humanSize(artifact.size_bytes)}
        </span>
      </header>
      {summarizable && (
        <div className="flex items-center gap-1 px-3 py-1.5 border-b border-border bg-elevated/40">
          <ToggleBtn
            active={view === "summary"}
            onClick={() => setView("summary")}
            icon={<Sparkles size={12} />}
            label="Summary"
          />
          <ToggleBtn
            active={view === "raw"}
            onClick={() => setView("raw")}
            icon={<Code2 size={12} />}
            label="Raw"
          />
          <div className="ml-auto text-[11px] text-muted">
            {artifact.role}
          </div>
        </div>
      )}
      <div className="flex-1 min-h-0">
        {view === "summary" && summarizable ? (
          <SummaryView artifact={artifact} />
        ) : (
          <RawView artifact={artifact} />
        )}
      </div>
    </div>
  );
}

function ToggleBtn({
  active,
  onClick,
  icon,
  label,
}: {
  active: boolean;
  onClick: () => void;
  icon: React.ReactNode;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs transition-colors",
        active
          ? "bg-accent-soft text-accent"
          : "text-fg/70 hover:text-fg hover:bg-elevated",
      )}
    >
      {icon}
      {label}
    </button>
  );
}

function SummaryView({ artifact }: { artifact: Artifact }) {
  const summary = useMutation({
    mutationFn: () =>
      api.summarize(artifact.rel_path, artifact.role, artifact.kind),
  });
  if (summary.isIdle) {
    return (
      <div className="p-4 flex flex-col items-start gap-2 text-sm">
        <p className="text-fg/75 leading-relaxed">
          Translate this artifact into plain English for a domain expert
          using GPT-5.4 (reasoning · medium).
        </p>
        <button
          onClick={() => summary.mutate()}
          className="btn-primary"
        >
          <Sparkles size={13} />
          Summarize
        </button>
      </div>
    );
  }
  if (summary.isPending) {
    return (
      <div className="p-4 flex items-center gap-2 text-sm text-muted">
        <Loader2 size={14} className="animate-spin" />
        Asking GPT-5.4…
      </div>
    );
  }
  if (summary.isError) {
    return (
      <div className="p-4 space-y-3 text-sm">
        <div className="text-danger">
          Summarization failed: {(summary.error as Error).message}
        </div>
        <button onClick={() => summary.mutate()} className="btn-outline">
          <RefreshCw size={13} />
          Retry
        </button>
      </div>
    );
  }
  if (summary.isSuccess) {
    const r = summary.data!.result;
    return (
      <div className="p-4 space-y-3 text-sm">
        <p className="leading-relaxed text-fg/90 text-balance">{r.summary}</p>
        {r.bullets.length > 0 && (
          <ul className="space-y-1.5">
            {r.bullets.map((b, i) => (
              <li key={i} className="flex items-start gap-2">
                <span className="text-accent mt-1.5 inline-block h-1 w-1 rounded-full bg-accent" />
                <span className="text-fg/80 leading-snug">{b}</span>
              </li>
            ))}
          </ul>
        )}
        <div className="text-[11px] text-muted pt-1">
          {r.cached ? "cached" : "fresh"} · {r.model} · effort: {r.reasoning_effort}
        </div>
      </div>
    );
  }
  return null;
}

function RawView({ artifact }: { artifact: Artifact }) {
  const content = useQuery({
    queryKey: ["artifact-content", artifact.rel_path],
    queryFn: () =>
      api.getArtifact(artifact.rel_path.split("/")[3] ?? "", artifact.rel_path),
  });
  if (content.isLoading) {
    return (
      <div className="p-4 flex items-center gap-2 text-sm text-muted">
        <Loader2 size={14} className="animate-spin" />
        Loading…
      </div>
    );
  }
  if (content.isError) {
    return (
      <div className="p-4 text-sm text-danger">
        Failed to read artifact: {(content.error as Error).message}
      </div>
    );
  }
  const data = content.data!;
  if (!data.text) {
    return (
      <div className="p-4 text-sm text-muted">
        Binary or unsupported artifact ({data.kind}, {humanSize(data.size_bytes)}).
      </div>
    );
  }
  return (
    <div>
      <pre className="text-[12px] leading-relaxed whitespace-pre-wrap font-mono text-fg/90 max-h-80 overflow-auto px-4 py-3">
        {data.text}
      </pre>
      {data.truncated && (
        <div className="px-4 pb-3 text-[11px] text-muted">
          (truncated preview)
        </div>
      )}
    </div>
  );
}
