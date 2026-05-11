/* Lazy embedding loader using transformers.js (Xenova/bge-small-en-v1.5).

   Triggered on first user interaction with the search box. Runs entirely in
   the browser; no API key, no proxy. The model is cached by the browser's
   Cache API after first download (~30 MB) and survives across visits.

   Exposes window.embedLoader:
     warmup()          → starts model fetch+init in the background
     ready             → Promise<void> resolved when model is callable
     embed(text)       → Promise<Float32Array(384)>
     status            → "idle" | "loading" | "ready" | "failed"
     onStatusChange(f) → subscribe to status transitions
*/

(() => {
  const MODEL_ID = "Xenova/bge-small-en-v1.5";
  // Pin the transformers.js version. The CDN serves the ESM bundle.
  const TRANSFORMERS_URL = "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.6.3/dist/transformers.min.js";

  let pipelinePromise = null;
  let extractor = null;
  let status = "idle";
  const listeners = new Set();

  function setStatus(s) {
    status = s;
    for (const l of listeners) {
      try { l(s); } catch (e) { /* ignore */ }
    }
  }

  async function _init() {
    setStatus("loading");
    let pipeline;
    try {
      const mod = await import(TRANSFORMERS_URL);
      pipeline = mod.pipeline;
      // Use full-fidelity weights when available; transformers.js will pick
      // an appropriate quantization automatically.
    } catch (err) {
      console.error("transformers.js import failed:", err);
      setStatus("failed");
      throw err;
    }
    try {
      // pooling: 'cls' matches the bge family's recommended pooling. The
      // Xenova/bge-small-en-v1.5 model card explicitly documents this.
      extractor = await pipeline("feature-extraction", MODEL_ID, {
        device: "wasm",
      });
      setStatus("ready");
    } catch (err) {
      console.error("model load failed:", err);
      setStatus("failed");
      throw err;
    }
  }

  function warmup() {
    if (!pipelinePromise) pipelinePromise = _init();
    return pipelinePromise;
  }

  async function ready() {
    return warmup();
  }

  async function embed(text) {
    if (!extractor) await warmup();
    if (!extractor) throw new Error("embedding model failed to load");
    // bge-small-en-v1.5: queries are encoded with a "query: " prefix; this
    // is the convention in the model card and is preserved in the Xenova
    // mirror. The corpus side uses no prefix.
    const tagged = `query: ${text}`;
    const out = await extractor(tagged, { pooling: "cls", normalize: true });
    // out.data is Float32Array of length 384 (or 1×384). out.dims = [1, 384].
    // We always want the flat 384-dim vector.
    const dim = out.dims[out.dims.length - 1];
    const flat = new Float32Array(out.data.length);
    flat.set(out.data);
    if (flat.length !== dim) {
      // Multi-batch case shouldn't happen with a single string, but be safe.
      const single = flat.subarray(0, dim);
      const copy = new Float32Array(dim);
      copy.set(single);
      return copy;
    }
    return flat;
  }

  window.embedLoader = {
    warmup, ready, embed,
    get status() { return status; },
    onStatusChange(f) { listeners.add(f); return () => listeners.delete(f); },
    MODEL_ID,
  };
})();
