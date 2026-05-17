"use client";

import { api, EnvView, TaskView, Artifact } from "@/lib/api";
import { useStore } from "@/lib/store";
import { useQuery } from "@tanstack/react-query";
import * as Tabs from "@radix-ui/react-tabs";
import {
  AlertCircle,
  BookOpen,
  ClipboardCheck,
  Database,
  ExternalLink,
  FileCode2,
  FileText,
  Image as ImageIcon,
  Loader2,
  ScrollText,
  ShieldAlert,
} from "lucide-react";
import { useMemo, useState } from "react";
import { Empty } from "@/components/ui/Empty";
import { cn } from "@/lib/cn";
import { InteractionHistory } from "@/components/InteractionHistory";
import { ArtifactCard } from "@/components/ArtifactCard";

type TabId = "audit" | "history";

const TABS: { id: TabId; label: string; icon: typeof FileText }[] = [
  { id: "audit", label: "Audit Files", icon: FileText },
  { id: "history", label: "Interaction History", icon: ScrollText },
];

export function InspectionPanel() {
  const selection = useStore((s) => s.selection);
  const [tab, setTab] = useState<TabId>("audit");

  const env = useQuery({
    queryKey: ["env", selection.envDir],
    queryFn: () => api.getEnv(selection.envDir!),
    enabled: !!selection.envDir,
  });

  const task = useQuery({
    queryKey: ["task", selection.envDir, selection.taskId],
    queryFn: () => api.getTask(selection.envDir!, selection.taskId!),
    enabled: !!selection.envDir && !!selection.taskId && !selection.isNewTask,
  });

  const hasSelection = !!selection.envDir;

  return (
    <div className="panel flex flex-col h-full overflow-hidden">
      <Tabs.Root
        value={tab}
        onValueChange={(v) => setTab(v as TabId)}
        className="flex flex-col h-full"
      >
        <Tabs.List className="flex items-center gap-1 px-3 py-2 border-b border-border bg-elevated/40">
          {TABS.map(({ id, label, icon: Icon }) => (
            <Tabs.Trigger
              key={id}
              value={id}
              className={cn(
                "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-medium transition-colors",
                "data-[state=active]:bg-accent-soft data-[state=active]:text-accent",
                "text-fg/70 hover:text-fg hover:bg-elevated",
              )}
            >
              <Icon size={14} />
              {label}
            </Tabs.Trigger>
          ))}
        </Tabs.List>

        <Tabs.Content value="audit" className="flex-1 overflow-y-auto p-4">
          {!hasSelection && <PickSomething />}
          {hasSelection && env.isLoading && <Loading />}
          {hasSelection && env.data && !selection.taskId && !selection.isNewTask && (
            <EnvAudit envView={env.data} />
          )}
          {hasSelection && task.data && !selection.isNewTask && (
            <TaskAudit envView={env.data ?? null} taskView={task.data} />
          )}
          {hasSelection && selection.isNewTask && env.data && (
            <NewTaskInspection envView={env.data} />
          )}
        </Tabs.Content>

        <Tabs.Content value="history" className="flex-1 overflow-hidden">
          <InteractionHistory />
        </Tabs.Content>
      </Tabs.Root>
    </div>
  );
}

function PickSomething() {
  return (
    <Empty
      icon={<BookOpen size={32} />}
      title="Pick a software to inspect"
      hint="Use the picker chip below to select an environment or task. Inspection details show up here — task description, scripts, audit verdict, evidence, and data files."
    />
  );
}

function Loading() {
  return (
    <div className="flex items-center justify-center py-16 text-muted gap-2">
      <Loader2 size={16} className="animate-spin" />
      Loading inspection…
    </div>
  );
}

function EnvAudit({ envView }: { envView: EnvView }) {
  const envSpec = envView.artifacts.find((a) => a.role === "env_spec");
  const scripts = envView.artifacts.filter(
    (a) => a.role === "install_script" || a.role === "setup_script" || a.role === "script",
  );
  return (
    <div className="space-y-6">
      <Header
        title={envView.spec_id}
        description={envView.description}
        meta={[
          envView.runner && `runner: ${envView.runner}`,
          envView.base_preset && `base: ${envView.base_preset}`,
          `${envView.tasks.length} tasks`,
        ].filter(Boolean) as string[]}
        tags={envView.tags}
      />

      <Section title="Environment Spec" icon={FileText}>
        {envSpec ? (
          <ArtifactCard artifact={envSpec} />
        ) : (
          <Empty title="No env.json found" />
        )}
      </Section>

      <Section title="Scripts" icon={FileCode2}>
        {scripts.length === 0 ? (
          <Empty title="No install / setup scripts" />
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {scripts.map((a) => (
              <ArtifactCard key={a.rel_path} artifact={a} />
            ))}
          </div>
        )}
      </Section>

      <Section title="Data Files" icon={Database}>
        {envView.data_files.length === 0 && envView.external_sources.length === 0 ? (
          <Empty title="No data files surfaced" hint="Files under config/, data/, fixtures/, or datasets/ would appear here." />
        ) : (
          <div className="space-y-3">
            {envView.external_sources.length > 0 && (
              <div className="panel p-3 space-y-2">
                <div className="text-xs uppercase tracking-wider text-muted">
                  External sources discovered in scripts
                </div>
                <ul className="space-y-1.5 text-sm">
                  {envView.external_sources.slice(0, 16).map((src) => (
                    <li key={src.url} className="flex items-start gap-2">
                      <ExternalLink size={12} className="mt-1 text-accent shrink-0" />
                      <div className="min-w-0">
                        <div className="font-mono text-xs text-fg/90 break-all">
                          {src.url}
                        </div>
                        <div className="text-[11px] text-muted truncate">
                          from {src.discovered_in}
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {envView.data_files.length > 0 && (
              <div className="grid gap-3 md:grid-cols-2">
                {envView.data_files.slice(0, 24).map((a) => (
                  <ArtifactCard key={a.rel_path} artifact={a} />
                ))}
              </div>
            )}
          </div>
        )}
      </Section>

      <Section title="Audit Verdict" icon={ShieldAlert}>
        {envView.audit_report ? (
          <div className="panel p-4 space-y-2">
            <div className="text-xs text-muted">{envView.audit_report.rel_path}</div>
            <pre className="text-xs leading-relaxed whitespace-pre-wrap font-mono text-fg/85 max-h-72 overflow-auto">
              {envView.audit_report.snippet}
            </pre>
          </div>
        ) : (
          <Empty title="No audit on file" hint="Run the audit phase to generate audit_<env>.md. Expert nudges with route=audit will trigger this." />
        )}
      </Section>

      <Section title="Auto-Check" icon={ClipboardCheck}>
        <ComingSoon hint="Programmatic env-setup checks. Wiring in a later milestone — see PROGRESS.md." />
      </Section>

      <Section title="Evidence Docs" icon={ImageIcon}>
        {envView.evidence_docs.length === 0 ? (
          <Empty title="No evidence captured" hint="The creator should produce evidence_docs/ during env construction. Absence here means the audit will likely flag this env." />
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {envView.evidence_docs.slice(0, 24).map((a) => (
              <ArtifactCard key={a.rel_path} artifact={a} />
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function TaskAudit({ envView, taskView }: { envView: EnvView | null; taskView: TaskView }) {
  const taskSpec = taskView.artifacts.find((a) => a.role === "task_spec");
  const setup = taskView.artifacts.find((a) => a.role === "task_setup");
  const verifier = taskView.artifacts.find((a) => a.role === "verifier");
  const checklist = taskView.artifacts.find((a) => a.role === "vlm_checklist");
  const exportScript = taskView.artifacts.find((a) => a.role === "task_export");
  const pi = taskView.artifacts.find((a) => a.role === "privileged_info");
  return (
    <div className="space-y-6">
      <Header
        title={`${taskView.env_dir} / ${taskView.task_id}`}
        description={taskView.description}
        meta={[
          taskView.difficulty && `difficulty: ${taskView.difficulty}`,
          taskView.success_mode && `success: ${taskView.success_mode}`,
          taskView.max_steps && `max_steps: ${taskView.max_steps}`,
          taskView.timeout_sec && `timeout: ${taskView.timeout_sec}s`,
        ].filter(Boolean) as string[]}
        tags={envView?.tags ?? []}
      />

      <Section title="Task Description" icon={FileText}>
        {taskSpec ? (
          <ArtifactCard artifact={taskSpec} />
        ) : (
          <Empty title="No task.json — task is incomplete" />
        )}
      </Section>

      <Section title="Setup Script" icon={FileCode2}>
        {setup ? (
          <ArtifactCard artifact={setup} />
        ) : (
          <Empty title="No setup_task.sh" hint="Without a setup script the task can't start from a known state." />
        )}
      </Section>

      <Section title="Data Files" icon={Database}>
        {taskView.data_files.length === 0 ? (
          <Empty title="No data files captured for this task" />
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {taskView.data_files.map((a) => (
              <ArtifactCard key={a.rel_path} artifact={a} />
            ))}
          </div>
        )}
      </Section>

      <Section title="Verifier" icon={ShieldAlert}>
        {verifier ? (
          <ArtifactCard artifact={verifier} />
        ) : (
          <Empty title="No verifier.py — task is unverifiable" />
        )}
      </Section>

      <Section title="VLM Checklist" icon={ClipboardCheck}>
        {checklist ? (
          <ArtifactCard artifact={checklist} />
        ) : (
          <Empty title="No vlm_checklist.json" hint="The task will fall back to whichever success.mode is declared." />
        )}
      </Section>

      <Section title="Export + Privileged Info" icon={FileText}>
        <div className="grid gap-3 md:grid-cols-2">
          {exportScript && <ArtifactCard artifact={exportScript} />}
          {pi && <ArtifactCard artifact={pi} />}
          {!exportScript && !pi && (
            <Empty title="No export/PI files" />
          )}
        </div>
      </Section>

      <Section title="Auto-Check" icon={ClipboardCheck}>
        <ComingSoon hint="Per-task auto-check for setup correctness. Reserved layout slot." />
      </Section>
    </div>
  );
}

function NewTaskInspection({ envView }: { envView: EnvView }) {
  return (
    <div className="space-y-6">
      <Header
        title={`${envView.env_dir} · new task`}
        description={"This will dispatch propose-and-amplify with your feedback as the seed brief."}
        meta={[
          `${envView.tasks.length} existing tasks`,
          envView.runner && `runner: ${envView.runner}`,
        ].filter(Boolean) as string[]}
        tags={envView.tags}
      />
      <div className="panel p-4 flex items-start gap-3 text-sm">
        <AlertCircle size={16} className="text-purple mt-0.5 shrink-0" />
        <p className="text-fg/85 leading-relaxed">
          Submit a feedback below describing the task you want generated. The
          proposer will read your note, then the amplifier will expand it into
          one new task folder under{" "}
          <span className="font-mono text-fg">{envView.env_dir}/tasks/</span>.
        </p>
      </div>
    </div>
  );
}

function Header({
  title,
  description,
  meta,
  tags,
}: {
  title: string;
  description: string | null | undefined;
  meta: string[];
  tags: string[];
}) {
  return (
    <header className="space-y-2">
      <h2 className="heading text-xl font-semibold text-fg">{title}</h2>
      {description && (
        <p className="text-sm text-fg/75 leading-relaxed max-w-prose">
          {description}
        </p>
      )}
      <div className="flex flex-wrap gap-1.5 pt-1">
        {meta.map((m) => (
          <span key={m} className="chip">
            {m}
          </span>
        ))}
        {tags.slice(0, 6).map((t) => (
          <span key={t} className="chip-purple">
            {t}
          </span>
        ))}
      </div>
    </header>
  );
}

function Section({
  title,
  icon: Icon,
  children,
}: {
  title: string;
  icon: typeof FileText;
  children: React.ReactNode;
}) {
  return (
    <section className="space-y-3">
      <div className="flex items-center gap-2">
        <Icon size={14} className="text-accent" />
        <h3 className="text-xs uppercase tracking-[0.16em] text-muted font-display">
          {title}
        </h3>
      </div>
      <div>{children}</div>
    </section>
  );
}

function ComingSoon({ hint }: { hint: string }) {
  return (
    <div className="panel p-4 flex items-start gap-3 text-sm">
      <span className="chip-purple">Coming soon</span>
      <p className="text-fg/80 leading-relaxed">{hint}</p>
    </div>
  );
}
