"use client";

import { useStore } from "@/lib/store";
import { Sidebar } from "@/components/Sidebar";
import { InspectionPanel } from "@/components/InspectionPanel";
import { ChatComposer } from "@/components/ChatComposer";
import { MemoryPanel } from "@/components/MemoryPanel";
import { RunMonitor } from "@/components/RunMonitor";
import { VNCStage } from "@/components/VNCStage";
import { Empty } from "@/components/ui/Empty";
import { Brain, ExternalLink, Github, MonitorPlay } from "lucide-react";
import { useState } from "react";

export function Console() {
  const rightPanel = useStore((s) => s.rightPanel);
  const setRightPanel = useStore((s) => s.setRightPanel);
  const selection = useStore((s) => s.selection);
  const [activeRunId, setActiveRunId] = useState<string | null>(null);

  return (
    <div className="h-screen flex">
      <Sidebar />
      <main className="flex-1 min-w-0 flex flex-col">
        <TopBar
          onInspectMemory={() => setRightPanel(rightPanel === "memory" ? null : "memory")}
        />
        <div className="flex-1 min-h-0 grid grid-cols-1 lg:grid-cols-[1fr_1fr] gap-3 px-4 py-3 overflow-hidden">
          <div className="min-h-0 overflow-hidden">
            <InspectionPanel />
          </div>
          <div className="min-h-0 overflow-hidden flex flex-col gap-3">
            <div className="flex-1 min-h-0 overflow-hidden">
              <RightSlot envPicked={!!selection.envDir} />
            </div>
            {activeRunId && (
              <RunMonitor
                runId={activeRunId}
                onClose={() => setActiveRunId(null)}
              />
            )}
            <ChatComposer onSubmitted={(r) => r.run_id && setActiveRunId(r.run_id)} />
          </div>
        </div>
      </main>
      {rightPanel === "memory" && <MemoryPanel />}
    </div>
  );
}

function TopBar({ onInspectMemory }: { onInspectMemory: () => void }) {
  return (
    <header className="px-4 py-3 flex items-center gap-3 border-b border-border bg-surface/60 backdrop-blur">
      <Brain size={18} className="text-accent" />
      <div>
        <h1 className="heading text-lg font-semibold">Expert Console</h1>
        <p className="text-[11px] text-muted -mt-0.5">
          Nudge the creation-audit and propose-and-amplify pipelines
        </p>
      </div>
      <div className="ml-auto flex items-center gap-2">
        <button onClick={onInspectMemory} className="btn-outline">
          <ExternalLink size={13} />
          Inspect Memory
        </button>
        <button
          className="btn-ghost"
          disabled
          title="Push to GitHub / Discord — wiring is a TODO; UI affordance only for now."
        >
          <Github size={13} />
          Push to GitHub / Discord
        </button>
      </div>
    </header>
  );
}

function RightSlot({ envPicked }: { envPicked: boolean }) {
  if (envPicked) {
    return (
      <div className="panel h-full overflow-hidden flex flex-col">
        <VNCStage />
      </div>
    );
  }
  return (
    <div className="panel h-full overflow-y-auto">
      <Empty
        icon={<MonitorPlay size={28} />}
        title="Pick a software to enable VNC"
        hint="When an environment is selected, this side becomes a live VNC viewer of the running env. Pick one with the chip below to begin."
        className="py-12"
      />
      <div className="px-4 pb-6 text-[12px] leading-relaxed text-fg/75 space-y-2.5">
        <p>
          <span className="text-accent font-medium">Pick</span> a software with
          the chip below. The inspection panel on the left fills in with task
          descriptions, scripts, audit verdict, and evidence docs.
        </p>
        <p>
          <span className="text-accent font-medium">Send</span> short feedback
          to nudge the agents. Examples:
        </p>
        <ul className="ml-3 space-y-1 text-[12px]">
          <li>· "Odoo HR is using demo data — must use real."</li>
          <li>· "For 3D Slicer, the audit missed that the volume is empty."</li>
          <li>· "Generate a task that requires importing a real DICOM series."</li>
        </ul>
        <p>
          <span className="text-accent font-medium">Inspect Memory</span>{" "}
          (top-right) shows the pending diff that will be committed if you
          accept the agent's edits.
        </p>
      </div>
    </div>
  );
}
