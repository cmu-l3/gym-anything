"use client";

import { api } from "@/lib/api";
import { useStore } from "@/lib/store";
import { useQuery } from "@tanstack/react-query";
import {
  Database,
  FilePlus,
  FolderTree,
  GitCommitVertical,
  Globe,
  X,
} from "lucide-react";
import { Empty } from "@/components/ui/Empty";
import { cn } from "@/lib/cn";

export function MemoryPanel() {
  const setRightPanel = useStore((s) => s.setRightPanel);
  const envDir = useStore((s) => s.selection.envDir);

  const diff = useQuery({
    queryKey: ["memory-diff", envDir],
    queryFn: () => api.memoryDiff(envDir),
    refetchInterval: 5_000,
  });
  const envDiff = useQuery({
    queryKey: ["env-diff", envDir],
    queryFn: () => api.envDiff(envDir!),
    enabled: !!envDir,
    refetchInterval: 5_000,
  });
  const listing = useQuery({
    queryKey: ["memory", envDir],
    queryFn: () => api.listMemory(envDir),
  });

  return (
    <aside className="w-[420px] shrink-0 panel rounded-none border-y-0 border-r-0 flex flex-col">
      <header className="flex items-center gap-2 px-3 py-3 border-b border-border">
        <GitCommitVertical size={15} className="text-accent" />
        <div className="text-sm font-medium">Pending Changes</div>
        <span className="ml-auto text-[11px] text-muted">
          base: {diff.data?.base_ref ?? "HEAD"}
        </span>
        <button
          onClick={() => setRightPanel(null)}
          className="ml-2 text-fg/60 hover:text-fg"
          aria-label="Close"
        >
          <X size={14} />
        </button>
      </header>

      <div className="flex-1 overflow-y-auto p-3 space-y-5">
        <div>
          <SectionLabel
            icon={<GitCommitVertical size={12} />}
            title="Memory"
            count={diff.data?.files.length ?? 0}
            totals={
              diff.data
                ? {
                    additions: diff.data.total_additions,
                    deletions: diff.data.total_deletions,
                  }
                : undefined
            }
          />
          {diff.isLoading && <div className="text-xs text-muted">Loading diff…</div>}
          {diff.data && diff.data.files.length === 0 && (
            <Empty
              icon={<GitCommitVertical size={22} />}
              title="No pending memory changes"
              hint="Submit a feedback to see the new entries here."
              className="py-6"
            />
          )}
          {diff.data && diff.data.files.length > 0 && (
            <div className="space-y-3">
              {diff.data.files.map((f) => (
                <DiffCard key={f.rel_path} file={f} />
              ))}
            </div>
          )}
        </div>

        {envDir && (
          <div>
            <SectionLabel
              icon={<FolderTree size={12} />}
              title={`Environment · ${envDir}`}
              count={envDiff.data?.files.length ?? 0}
              totals={
                envDiff.data
                  ? {
                      additions: envDiff.data.total_additions,
                      deletions: envDiff.data.total_deletions,
                    }
                  : undefined
              }
            />
            {envDiff.isLoading && (
              <div className="text-xs text-muted">Loading env diff…</div>
            )}
            {envDiff.isError && (
              <div className="text-xs text-danger px-1">
                {(envDiff.error as Error).message}
              </div>
            )}
            {envDiff.data && envDiff.data.files.length === 0 && (
              <Empty
                icon={<FolderTree size={22} />}
                title="No pending env changes"
                hint="Pipeline runs that edit env scripts, tasks, or evidence_docs land here."
                className="py-6"
              />
            )}
            {envDiff.data && envDiff.data.files.length > 0 && (
              <div className="space-y-3">
                {envDiff.data.files.map((f) => (
                  <DiffCard key={f.rel_path} file={f} />
                ))}
              </div>
            )}
          </div>
        )}

        <div>
          <SectionLabel
            icon={<Globe size={12} />}
            title="General Memory"
            count={listing.data?.general.length ?? 0}
          />
          {listing.data?.general.slice(0, 8).map((m) => (
            <MemoryFileCard key={m.rel_path} file={m} />
          ))}
        </div>

        <div>
          <SectionLabel
            icon={<Database size={12} />}
            title={`Shared Memory${envDir ? ` · ${envDir}` : ""}`}
            count={listing.data?.specific.length ?? 0}
          />
          {(!listing.data || listing.data.specific.length === 0) && (
            <div className="text-xs text-muted px-1">
              {envDir
                ? "No env-specific notes yet."
                : "Pick a software to see its shared memory shards."}
            </div>
          )}
          {listing.data?.specific.slice(0, 8).map((m) => (
            <MemoryFileCard key={m.rel_path} file={m} />
          ))}
        </div>
      </div>
    </aside>
  );
}

function SectionLabel({
  icon,
  title,
  count,
  totals,
}: {
  icon: React.ReactNode;
  title: string;
  count: number;
  totals?: { additions: number; deletions: number };
}) {
  return (
    <div className="flex items-center gap-2 mb-2 px-1">
      <span className="text-accent">{icon}</span>
      <span className="text-[11px] uppercase tracking-[0.16em] text-muted font-display">
        {title}
      </span>
      <span className="ml-auto flex items-center gap-2 text-[10px] tabular-nums">
        {totals && totals.additions > 0 && (
          <span className="text-success">+{totals.additions}</span>
        )}
        {totals && totals.deletions > 0 && (
          <span className="text-danger">-{totals.deletions}</span>
        )}
        <span className="text-muted">{count}</span>
      </span>
    </div>
  );
}

function DiffCard({ file }: { file: import("@/lib/api").FileDiff }) {
  return (
    <div className="panel overflow-hidden text-[12px]">
      <header className="flex items-center gap-2 px-2.5 py-1.5 border-b border-border bg-elevated/40">
        <StatusDot status={file.status} />
        <div className="font-mono text-[11px] text-fg/80 truncate flex-1">
          {file.rel_path}
        </div>
        <span className="text-success text-[11px]">+{file.additions}</span>
        <span className="text-danger text-[11px]">-{file.deletions}</span>
      </header>
      <div className="max-h-44 overflow-y-auto font-mono leading-snug">
        {file.hunks.map((hunk, idx) => (
          <div key={idx}>
            <div className="px-2.5 py-1 text-muted text-[10px] bg-elevated/30 border-y border-border">
              {hunk.header}
            </div>
            {hunk.lines.map((l, i) => (
              <div
                key={i}
                className={cn(
                  "px-2.5 whitespace-pre",
                  l.startsWith("+") && "text-success bg-success/5",
                  l.startsWith("-") && "text-danger bg-danger/5",
                )}
              >
                {l}
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

function MemoryFileCard({ file }: { file: import("@/lib/api").MemoryFile }) {
  return (
    <div className="px-1 py-1.5 group">
      <div className="flex items-center gap-2">
        <FilePlus size={11} className="text-fg/60" />
        <div className="text-xs font-medium truncate">{file.name}</div>
        {file.is_expert_feedback && (
          <span className="chip-accent text-[10px] py-0">expert</span>
        )}
        {file.env_dir && (
          <span className="chip text-[10px] py-0">{file.env_dir}</span>
        )}
      </div>
      <div className="text-[10.5px] text-muted font-mono truncate">
        {file.rel_path}
      </div>
      {file.snippet && (
        <div className="text-[11px] text-fg/70 leading-snug line-clamp-2 mt-0.5">
          {file.snippet}
        </div>
      )}
    </div>
  );
}

function StatusDot({ status }: { status: string }) {
  const cls =
    status === "added"
      ? "bg-success"
      : status === "deleted"
      ? "bg-danger"
      : status === "renamed"
      ? "bg-purple"
      : "bg-accent";
  return <span className={cn("h-1.5 w-1.5 rounded-full shrink-0", cls)} />;
}
