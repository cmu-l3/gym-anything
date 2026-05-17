// Minimal store with a zustand-style `create` API, built on
// useSyncExternalStore. Keeps frontend deps tight (no zustand).

import { useSyncExternalStore } from "react";

type Updater<T> = (state: T) => Partial<T> | T;

export type StoreApi<T> = {
  getState: () => T;
  setState: (updater: Partial<T> | Updater<T>) => void;
  subscribe: (listener: () => void) => () => void;
};

function createStore<T extends object>(initial: T): StoreApi<T> {
  let state = initial;
  const listeners = new Set<() => void>();
  const setState: StoreApi<T>["setState"] = (updater) => {
    const patch =
      typeof updater === "function"
        ? (updater as Updater<T>)(state)
        : updater;
    const next = { ...state, ...patch } as T;
    if (Object.is(next, state)) return;
    state = next;
    listeners.forEach((l) => l());
  };
  return {
    getState: () => state,
    setState,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}

export function create<T extends object>(
  init: (set: StoreApi<T>["setState"], get: () => T) => T,
) {
  const placeholder: any = {};
  const api = createStore<T>(placeholder);
  Object.assign(placeholder, init(api.setState, api.getState));

  function useStore(): T;
  function useStore<U>(selector: (state: T) => U): U;
  function useStore<U>(selector?: (state: T) => U): U | T {
    const snap = useSyncExternalStore(
      api.subscribe,
      () => api.getState(),
      () => api.getState(),
    );
    return selector ? selector(snap) : snap;
  }
  (useStore as any).getState = api.getState;
  (useStore as any).setState = api.setState;
  return useStore as typeof useStore & Pick<StoreApi<T>, "getState" | "setState">;
}
