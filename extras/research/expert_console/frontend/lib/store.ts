// Lightweight session store for the picker + active selection.

"use client";

import { create } from "@/lib/zustand-shim";

export type Selection = {
  envDir: string | null;
  taskId: string | null;
  isNewTask: boolean;
};

export type Store = {
  selection: Selection;
  sessionId: string | null;
  rightPanel: "memory" | null;
  pickerOpen: boolean;
  setSelection: (sel: Partial<Selection>) => void;
  setSessionId: (id: string | null) => void;
  setRightPanel: (panel: Store["rightPanel"]) => void;
  setPickerOpen: (open: boolean) => void;
  clearSelection: () => void;
};

export const useStore = create<Store>((set) => ({
  selection: { envDir: null, taskId: null, isNewTask: false },
  sessionId: null,
  rightPanel: null,
  pickerOpen: false,
  setSelection: (sel) =>
    set((s) => ({ selection: { ...s.selection, ...sel } })),
  setSessionId: (id) => set({ sessionId: id }),
  setRightPanel: (panel) => set({ rightPanel: panel }),
  setPickerOpen: (open) => set({ pickerOpen: open }),
  clearSelection: () =>
    set({ selection: { envDir: null, taskId: null, isNewTask: false } }),
}));
