// Typed client for the expert-console backend.

export type SoftwareEntry = {
  env_dir: string;
  spec_id: string;
  description: string | null;
  tags: string[];
  runner: string | null;
  task_count: number;
};

export type TaskSummary = {
  task_id: string;
  env_dir: string;
  description: string | null;
  difficulty: string | null;
  success_mode: string | null;
  has_vlm_checklist: boolean;
};

export type Artifact = {
  name: string;
  rel_path: string;
  role: string;
  kind: string;
  size_bytes: number;
};

export type ExternalSource = { url: string; discovered_in: string };

export type AuditReport = { rel_path: string; size_bytes: number; snippet: string };

export type EnvView = {
  env_dir: string;
  spec_id: string;
  description: string | null;
  tags: string[];
  runner: string | null;
  base_preset: string | null;
  artifacts: Artifact[];
  data_files: Artifact[];
  external_sources: ExternalSource[];
  evidence_docs: Artifact[];
  audit_report: AuditReport | null;
  tasks: TaskSummary[];
};

export type TaskView = {
  env_dir: string;
  task_id: string;
  description: string | null;
  difficulty: string | null;
  success_mode: string | null;
  natural_language: string | null;
  max_steps: number | null;
  timeout_sec: number | null;
  artifacts: Artifact[];
  vlm_checklist_present: boolean;
  data_files: Artifact[];
};

export type ArtifactContent = {
  rel_path: string;
  kind: string;
  size_bytes: number;
  text: string | null;
  truncated: boolean;
};

export type SummaryResult = {
  summary: string;
  bullets: string[];
  cached: boolean;
  model: string;
  reasoning_effort: string;
};

export type SummarizeResponse = {
  rel_path: string;
  kind: string;
  truncated: boolean;
  result: SummaryResult;
};

export type MemoryFile = {
  rel_path: string;
  name: string;
  tier: "general" | "specific";
  pipeline: string;
  is_expert_feedback: boolean;
  size_bytes: number;
  env_dir: string | null;
  snippet: string | null;
};

export type MemoryListing = {
  general: MemoryFile[];
  specific: MemoryFile[];
};

export type DiffHunk = { header: string; lines: string[] };

export type FileDiff = {
  rel_path: string;
  status: "modified" | "added" | "deleted" | "renamed";
  old_path: string | null;
  additions: number;
  deletions: number;
  hunks: DiffHunk[];
};

export type MemoryDiff = {
  base_ref: string;
  total_additions: number;
  total_deletions: number;
  files: FileDiff[];
};

export type FeedbackSubmission = {
  session_id?: string | null;
  message: string;
  route: "audit" | "creator";
  memory_tier: "general" | "specific";
  suggest_checklist_change: boolean;
  env_dir: string | null;
  task_id: string | null;
  is_new_task: boolean;
};

export type FeedbackResponse = {
  feedback_id: string;
  session_id: string;
  memory_entry: { rel_path: string; anchor: string; timestamp: string };
  run_id: string | null;
  pipeline: string | null;
  command: string[] | null;
  dispatched: boolean;
};

export type SessionSummary = {
  id: string;
  title: string;
  env_dir: string | null;
  task_id: string | null;
  status: string;
  created_at: string;
  updated_at: string;
  feedback_count: number;
  run_count: number;
};

export type FeedbackRecord = {
  id: string;
  message: string;
  route: string;
  memory_tier: string;
  suggest_checklist_change: boolean;
  env_dir: string | null;
  task_id: string | null;
  is_new_task: boolean;
  appended_to_path: string | null;
  entry_anchor: string | null;
  created_at: string;
};

export type RunSummary = {
  id: string;
  session_id: string;
  feedback_id: string | null;
  pipeline: string;
  status: "pending" | "running" | "finished" | "failed" | "stopped";
  current_phase: string | null;
  exit_code: number | null;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
};

export type RunDetail = RunSummary & {
  command: string[];
  logs: { seq: number; stream: string; line: string; ts: string }[];
};

export type ChangesSummaryResp = {
  summary: string;
  bullets: string[];
  addressed_feedback: "yes" | "partial" | "no" | "unclear";
  addressed_reason: string;
  file_count: number;
  additions: number;
  deletions: number;
  cached: boolean;
  model: string;
  reasoning_effort: string;
};

export type SessionDetail = SessionSummary & {
  feedbacks: FeedbackRecord[];
  runs: RunSummary[];
};

export type Diagnostics = {
  repo_root: string;
  environments_dir: string;
  creation_audit_memory_dir: string;
  propose_amplify_memory_dir: string;
  db_path: string;
  state_dir: string;
  artifacts_dir: string;
  backend_host: string;
  backend_port: number;
  claude_bin: string | null;
  npm_bin: string | null;
  git_bin: string | null;
  openai_api_key_present: boolean;
  anthropic_api_key_present: boolean;
  gemini_api_key_present: boolean;
  env_count: number;
  creation_audit_memory_files: number;
  propose_amplify_memory_files: number;
  expert_feedback_files_present: boolean;
};

export type Preferences = {
  summarize_model: string;
  summarize_reasoning_effort: "minimal" | "low" | "medium" | "high";
  summarize_max_frames: number;
  summarize_max_tokens: number;
  summarize_timeout_sec: number;
  completion_threshold: number;
  integrity_threshold: number;
};

export type VNCStatus =
  | { active: false }
  | {
      active: true;
      id: string;
      env_dir: string;
      vnc_host: string;
      vnc_port: number;
      vnc_password: string | null;
      started_at: string;
      status: string;
      last_error: string | null;
    };

async function jfetch<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(path, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      ...(init?.headers || {}),
    },
  });
  // Read the body exactly once. The previous shape called `res.json()` then
  // `res.text()` on failure, which fails with "body stream already read" when
  // the JSON parse threw mid-read. Read text first, then try parsing.
  const raw = await res.text();
  if (!res.ok) {
    let detail: string = raw;
    try {
      const body = raw ? JSON.parse(raw) : null;
      if (body && typeof body === "object") {
        detail = (body as { detail?: unknown }).detail
          ? String((body as { detail: unknown }).detail)
          : JSON.stringify(body);
      }
    } catch {
      // raw wasn't JSON; leave detail = raw
    }
    throw new ApiError(res.status, detail || res.statusText);
  }
  if (!raw) {
    return undefined as unknown as T;
  }
  try {
    return JSON.parse(raw) as T;
  } catch (err) {
    throw new ApiError(
      res.status,
      `Server returned non-JSON body: ${raw.slice(0, 200)}`,
    );
  }
}

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export const api = {
  health: () => jfetch<{ status: string }>("/api/health"),
  listSoftware: () => jfetch<{ items: SoftwareEntry[]; count: number }>("/api/software"),
  getEnv: (env_dir: string) => jfetch<EnvView>(`/api/software/${encodeURIComponent(env_dir)}`),
  listTasks: (env_dir: string) =>
    jfetch<{ items: TaskSummary[]; count: number }>(`/api/software/${encodeURIComponent(env_dir)}/tasks`),
  getTask: (env_dir: string, task_id: string) =>
    jfetch<TaskView>(`/api/software/${encodeURIComponent(env_dir)}/tasks/${encodeURIComponent(task_id)}`),
  getArtifact: (env_dir: string, rel_path: string) =>
    jfetch<ArtifactContent>(
      `/api/software/${encodeURIComponent(env_dir)}/artifact?rel_path=${encodeURIComponent(rel_path)}`,
    ),
  summarize: (rel_path: string, artifact_role: string | null, kind_hint: string | null) =>
    jfetch<SummarizeResponse>("/api/summarize", {
      method: "POST",
      body: JSON.stringify({ rel_path, artifact_role, kind_hint, force: false }),
    }),
  listMemory: (env_dir: string | null) =>
    jfetch<MemoryListing>(`/api/memory${env_dir ? `?env_dir=${encodeURIComponent(env_dir)}` : ""}`),
  readMemoryFile: (rel_path: string) =>
    jfetch<{ rel_path: string; text: string }>(`/api/memory/file?rel_path=${encodeURIComponent(rel_path)}`),
  memoryDiff: (env_dir: string | null) =>
    jfetch<MemoryDiff>(`/api/memory/diff${env_dir ? `?env_dir=${encodeURIComponent(env_dir)}` : ""}`),
  envDiff: (env_dir: string) =>
    jfetch<MemoryDiff>(`/api/memory/diff/env?env_dir=${encodeURIComponent(env_dir)}`),
  submitFeedback: (payload: FeedbackSubmission) =>
    jfetch<FeedbackResponse>("/api/feedback", {
      method: "POST",
      body: JSON.stringify(payload),
    }),
  listSessions: () => jfetch<SessionSummary[]>("/api/sessions"),
  getSession: (id: string) => jfetch<SessionDetail>(`/api/sessions/${encodeURIComponent(id)}`),
  listRuns: (session_id?: string) =>
    jfetch<RunSummary[]>(`/api/runs${session_id ? `?session_id=${encodeURIComponent(session_id)}` : ""}`),
  getRun: (id: string) => jfetch<RunDetail>(`/api/runs/${encodeURIComponent(id)}`),
  stopRun: (id: string) =>
    jfetch<{ stopped: boolean; run_id: string }>(`/api/runs/${encodeURIComponent(id)}/stop`, {
      method: "POST",
    }),
  changesSummary: (id: string, force = false) =>
    jfetch<ChangesSummaryResp>(
      `/api/runs/${encodeURIComponent(id)}/changes-summary${force ? "?force=true" : ""}`,
    ),
  vncStatus: () => jfetch<VNCStatus>("/api/vnc"),
  vncStart: (env_dir: string) =>
    jfetch<VNCStatus>("/api/vnc/start", {
      method: "POST",
      body: JSON.stringify({ env_dir }),
    }),
  vncReset: (id: string) => jfetch<VNCStatus>(`/api/vnc/${encodeURIComponent(id)}/reset`, { method: "POST" }),
  vncStop: (id: string) =>
    jfetch<{ stopped: boolean; session_id: string }>(`/api/vnc/${encodeURIComponent(id)}/stop`, { method: "POST" }),
  diagnostics: () => jfetch<Diagnostics>("/api/settings/diagnostics"),
  getPreferences: () => jfetch<Preferences>("/api/settings/preferences"),
  updatePreferences: (patch: Partial<Preferences>) =>
    jfetch<Preferences>("/api/settings/preferences", {
      method: "PUT",
      body: JSON.stringify(patch),
    }),
  resetPreferences: () =>
    jfetch<Preferences>("/api/settings/preferences/reset", { method: "POST" }),
};
