"use client";

import { api, Diagnostics, Preferences } from "@/lib/api";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AlertCircle,
  CheckCircle2,
  Database,
  FolderOpen,
  Key,
  Loader2,
  RotateCcw,
  Save,
  Sparkles,
  Terminal,
  XCircle,
} from "lucide-react";
import { useEffect, useState } from "react";
import { cn } from "@/lib/cn";

const EFFORTS: Preferences["summarize_reasoning_effort"][] = [
  "minimal",
  "low",
  "medium",
  "high",
];

export function SettingsPanel() {
  const qc = useQueryClient();
  const diagnostics = useQuery({
    queryKey: ["diagnostics"],
    queryFn: () => api.diagnostics(),
    refetchInterval: 15_000,
  });
  const prefs = useQuery({
    queryKey: ["preferences"],
    queryFn: () => api.getPreferences(),
  });

  const [draft, setDraft] = useState<Preferences | null>(null);
  useEffect(() => {
    if (prefs.data) setDraft(prefs.data);
  }, [prefs.data]);

  const dirty =
    draft != null &&
    prefs.data != null &&
    JSON.stringify(draft) !== JSON.stringify(prefs.data);

  const save = useMutation({
    mutationFn: () => api.updatePreferences(draft!),
    onSuccess: (data) => {
      qc.setQueryData(["preferences"], data);
      setDraft(data);
    },
  });

  const reset = useMutation({
    mutationFn: () => api.resetPreferences(),
    onSuccess: (data) => {
      qc.setQueryData(["preferences"], data);
      setDraft(data);
    },
  });

  return (
    <div className="px-2 py-2 space-y-4 text-xs">
      <SectionLabel title="Runtime" icon={<Terminal size={12} />} />
      <Diag data={diagnostics.data} loading={diagnostics.isLoading} />

      <SectionLabel title="Summarization" icon={<Sparkles size={12} />} />
      {prefs.isLoading || draft == null ? (
        <div className="text-muted">Loading preferences…</div>
      ) : (
        <PreferencesForm
          draft={draft}
          setDraft={setDraft}
          onSave={() => save.mutate()}
          onReset={() => reset.mutate()}
          dirty={dirty}
          saving={save.isPending}
          resetting={reset.isPending}
          error={
            save.isError
              ? (save.error as Error).message
              : reset.isError
              ? (reset.error as Error).message
              : null
          }
        />
      )}
    </div>
  );
}

function SectionLabel({
  title,
  icon,
}: {
  title: string;
  icon: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-1.5 px-1 text-[10px] uppercase tracking-[0.16em] text-muted font-display">
      <span className="text-accent">{icon}</span>
      {title}
    </div>
  );
}

function Diag({
  data,
  loading,
}: {
  data: Diagnostics | undefined;
  loading: boolean;
}) {
  if (loading || !data) {
    return (
      <div className="px-1 text-muted">
        <Loader2 size={12} className="inline animate-spin mr-1" />
        Loading runtime info…
      </div>
    );
  }
  return (
    <div className="space-y-2.5">
      <Row label="Backend" value={`${data.backend_host}:${data.backend_port}`} />
      <KeyRow label="OPENAI_API_KEY" present={data.openai_api_key_present} />
      <KeyRow
        label="ANTHROPIC_API_KEY"
        present={data.anthropic_api_key_present}
      />
      <KeyRow label="GEMINI_API_KEY" present={data.gemini_api_key_present} />
      <BinRow label="claude" value={data.claude_bin} />
      <BinRow label="npm" value={data.npm_bin} />
      <BinRow label="git" value={data.git_bin} />
      <PathRow label="repo" value={data.repo_root} icon={<FolderOpen size={11} />} />
      <PathRow label="state" value={data.state_dir} icon={<Database size={11} />} />
      <PathRow label="db" value={data.db_path} icon={<Database size={11} />} />
      <Row label="environments" value={`${data.env_count}`} />
      <Row
        label="memory files"
        value={`${data.creation_audit_memory_files} + ${data.propose_amplify_memory_files}`}
      />
      <Row
        label="expert feedback files"
        value={data.expert_feedback_files_present ? "present" : "missing"}
        ok={data.expert_feedback_files_present}
      />
    </div>
  );
}

function Row({
  label,
  value,
  ok,
}: {
  label: string;
  value: string;
  ok?: boolean;
}) {
  return (
    <div className="flex items-center gap-2 px-1">
      <span className="text-muted flex-1 truncate">{label}</span>
      <span
        className={cn(
          "text-fg/85 font-mono truncate",
          ok === false && "text-danger",
          ok === true && "text-success",
        )}
        title={value}
      >
        {value}
      </span>
    </div>
  );
}

function KeyRow({ label, present }: { label: string; present: boolean }) {
  return (
    <div className="flex items-center gap-2 px-1">
      <Key size={11} className="text-muted shrink-0" />
      <span className="text-muted flex-1 truncate font-mono">{label}</span>
      {present ? (
        <span className="inline-flex items-center gap-1 text-success">
          <CheckCircle2 size={11} />
          set
        </span>
      ) : (
        <span className="inline-flex items-center gap-1 text-danger">
          <XCircle size={11} />
          unset
        </span>
      )}
    </div>
  );
}

function BinRow({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="flex items-center gap-2 px-1">
      <Terminal size={11} className="text-muted shrink-0" />
      <span className="text-muted w-14 font-mono">{label}</span>
      {value ? (
        <span
          className="text-fg/80 font-mono text-[11px] truncate flex-1"
          title={value}
        >
          {value}
        </span>
      ) : (
        <span className="text-danger flex-1">not found</span>
      )}
    </div>
  );
}

function PathRow({
  label,
  value,
  icon,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-2 px-1">
      <span className="text-muted shrink-0">{icon}</span>
      <span className="text-muted w-14 font-mono">{label}</span>
      <span className="text-fg/80 font-mono text-[11px] truncate flex-1" title={value}>
        {value}
      </span>
    </div>
  );
}

function PreferencesForm({
  draft,
  setDraft,
  onSave,
  onReset,
  dirty,
  saving,
  resetting,
  error,
}: {
  draft: Preferences;
  setDraft: (p: Preferences) => void;
  onSave: () => void;
  onReset: () => void;
  dirty: boolean;
  saving: boolean;
  resetting: boolean;
  error: string | null;
}) {
  return (
    <div className="space-y-2.5 px-1">
      <Field label="Model">
        <input
          value={draft.summarize_model}
          onChange={(e) =>
            setDraft({ ...draft, summarize_model: e.target.value })
          }
          className="input text-xs py-1"
        />
      </Field>
      <Field label="Reasoning">
        <div className="flex gap-1 flex-wrap">
          {EFFORTS.map((e) => (
            <button
              key={e}
              onClick={() =>
                setDraft({ ...draft, summarize_reasoning_effort: e })
              }
              className={cn(
                "px-2 py-0.5 rounded-md text-[11px] transition-colors",
                draft.summarize_reasoning_effort === e
                  ? "bg-accent-soft text-accent"
                  : "bg-elevated text-fg/70 hover:text-fg",
              )}
            >
              {e}
            </button>
          ))}
        </div>
      </Field>
      <Field label="Max tokens">
        <input
          type="number"
          value={draft.summarize_max_tokens}
          onChange={(e) =>
            setDraft({
              ...draft,
              summarize_max_tokens: Number(e.target.value),
            })
          }
          className="input text-xs py-1"
        />
      </Field>
      <Field label="Timeout (s)">
        <input
          type="number"
          value={draft.summarize_timeout_sec}
          onChange={(e) =>
            setDraft({
              ...draft,
              summarize_timeout_sec: Number(e.target.value),
            })
          }
          className="input text-xs py-1"
        />
      </Field>
      <Field label="Completion %">
        <input
          type="number"
          step="1"
          min="0"
          max="100"
          value={draft.completion_threshold}
          onChange={(e) =>
            setDraft({
              ...draft,
              completion_threshold: Number(e.target.value),
            })
          }
          className="input text-xs py-1"
        />
      </Field>
      <Field label="Integrity">
        <input
          type="number"
          step="0.05"
          min="0"
          max="1"
          value={draft.integrity_threshold}
          onChange={(e) =>
            setDraft({
              ...draft,
              integrity_threshold: Number(e.target.value),
            })
          }
          className="input text-xs py-1"
        />
      </Field>
      {error && (
        <div className="text-danger flex items-start gap-1 px-1 leading-snug">
          <AlertCircle size={11} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </div>
      )}
      <div className="flex items-center gap-2 pt-1">
        <button
          onClick={onSave}
          disabled={!dirty || saving}
          className="btn-primary text-xs py-1"
        >
          <Save size={11} />
          {saving ? "Saving…" : "Save"}
        </button>
        <button
          onClick={onReset}
          disabled={resetting}
          className="btn-ghost text-xs py-1"
        >
          <RotateCcw size={11} />
          {resetting ? "Resetting…" : "Reset to defaults"}
        </button>
      </div>
    </div>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[10px] uppercase tracking-wider text-muted px-1">
        {label}
      </span>
      {children}
    </label>
  );
}
