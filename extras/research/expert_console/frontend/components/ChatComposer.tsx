"use client";

import { api, FeedbackResponse } from "@/lib/api";
import { useStore } from "@/lib/store";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  AlertCircle,
  ClipboardList,
  Database,
  Globe,
  SendHorizontal,
  Sparkles,
  UserCheck,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/cn";
import { SoftwarePicker } from "@/components/SoftwarePicker";

type Route = "creator" | "audit";
type MemTier = "general" | "specific";

export function ChatComposer({
  onSubmitted,
}: {
  onSubmitted: (r: FeedbackResponse) => void;
}) {
  const selection = useStore((s) => s.selection);
  const sessionId = useStore((s) => s.sessionId);
  const setSessionId = useStore((s) => s.setSessionId);
  const qc = useQueryClient();

  const [topInput, setTopInput] = useState("");
  const [message, setMessage] = useState("");
  const [route, setRoute] = useState<Route>("creator");
  const [memTier, setMemTier] = useState<MemTier>("general");
  const [checklist, setChecklist] = useState(false);

  // Mirror env-picker state onto the default memory tier so we don't quietly
  // append a GLOBAL entry when the expert is clearly nudging one env. The
  // expert can still flip it manually after this defaulting fires.
  const userTouchedTierRef = useRef(false);
  useEffect(() => {
    if (userTouchedTierRef.current) return;
    setMemTier(selection.envDir ? "specific" : "general");
  }, [selection.envDir]);

  const submit = useMutation({
    mutationFn: () =>
      api.submitFeedback({
        session_id: sessionId,
        message,
        route,
        memory_tier: selection.envDir ? memTier : "general",
        suggest_checklist_change: checklist,
        env_dir: selection.envDir,
        task_id: selection.taskId,
        is_new_task: selection.isNewTask,
      }),
    onSuccess: (resp) => {
      setSessionId(resp.session_id);
      setMessage("");
      setChecklist(false);
      qc.invalidateQueries({ queryKey: ["sessions"] });
      qc.invalidateQueries({ queryKey: ["session", resp.session_id] });
      qc.invalidateQueries({ queryKey: ["memory"] });
      qc.invalidateQueries({ queryKey: ["memory-diff"] });
      onSubmitted(resp);
    },
  });

  const isTaskLevel = !!selection.taskId || selection.isNewTask;
  const showAuditCreator = !isTaskLevel;
  const showMemoryTier = !!selection.envDir;

  const composed = topInput.trim()
    ? `${topInput.trim()}\n\n${message.trim()}`.trim()
    : message.trim();

  function handleSend() {
    if (!composed) return;
    setMessage(composed);
    submit.mutate();
  }

  return (
    <section className="panel p-3 space-y-3">
      <div>
        <div className="flex items-center gap-2 mb-1.5">
          <span className="text-[11px] uppercase tracking-wider text-muted font-display">
            Target
          </span>
          <SoftwarePicker />
        </div>
        <div className="flex items-start gap-2">
          <input
            value={topInput}
            onChange={(e) => setTopInput(e.target.value)}
            placeholder="What task is on your mind? (optional — gets prepended to your feedback)"
            className="input"
          />
        </div>
      </div>

      <div className="space-y-1.5">
        <span className="text-[11px] uppercase tracking-wider text-muted font-display">
          Feedback
        </span>
        <textarea
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          placeholder="Feedback to add to memory / checklists?  (e.g. 'use real data, not demo data')"
          rows={3}
          className="input resize-none leading-relaxed"
        />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {showAuditCreator && (
          <SegToggle
            label="To"
            value={route}
            onChange={setRoute}
            options={[
              { value: "creator", label: "Creator", icon: <Sparkles size={12} /> },
              { value: "audit", label: "Audit", icon: <UserCheck size={12} /> },
            ]}
          />
        )}
        {isTaskLevel && (
          <span className="chip-accent">
            <ClipboardList size={12} />
            to proposer (task scope)
          </span>
        )}
        {showMemoryTier && (
          <SegToggle
            label="Memory"
            value={memTier}
            onChange={(v) => {
              userTouchedTierRef.current = true;
              setMemTier(v);
            }}
            options={[
              { value: "general", label: "General", icon: <Globe size={12} /> },
              {
                value: "specific",
                label: "Specific",
                icon: <Database size={12} />,
              },
            ]}
          />
        )}
        {!showMemoryTier && (
          <span className="chip">
            <Globe size={12} />
            memory: general
          </span>
        )}
        {!isTaskLevel && (
          <ToggleChip
            active={checklist}
            onClick={() => setChecklist((v) => !v)}
            icon={<ClipboardList size={12} />}
            label="Suggest audit checklist change"
          />
        )}
        <div className="ml-auto flex items-center gap-2">
          {submit.isError && (
            <span className="text-xs text-danger inline-flex items-center gap-1">
              <AlertCircle size={12} />
              {(submit.error as Error).message}
            </span>
          )}
          <button
            disabled={!composed.trim() || submit.isPending}
            onClick={handleSend}
            className="btn-primary"
          >
            <SendHorizontal size={13} />
            {submit.isPending ? "Sending…" : "Send"}
          </button>
        </div>
      </div>
    </section>
  );
}

function SegToggle<T extends string>({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: string; icon?: React.ReactNode }[];
}) {
  return (
    <div className="inline-flex items-center gap-1 panel px-1.5 py-1 rounded-md">
      <span className="text-[10px] uppercase tracking-wider text-muted px-1">
        {label}
      </span>
      <div className="flex items-center gap-0.5">
        {options.map((o) => (
          <button
            key={o.value}
            type="button"
            onClick={() => onChange(o.value)}
            className={cn(
              "px-2 py-0.5 rounded-md text-xs inline-flex items-center gap-1 transition-colors",
              value === o.value
                ? "bg-accent-soft text-accent"
                : "text-fg/70 hover:text-fg hover:bg-elevated",
            )}
          >
            {o.icon}
            {o.label}
          </button>
        ))}
      </div>
    </div>
  );
}

function ToggleChip({
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
      type="button"
      onClick={onClick}
      className={cn(
        "chip transition-colors",
        active && "border-accent/40 text-accent bg-accent-soft",
      )}
    >
      {icon}
      {label}
    </button>
  );
}
