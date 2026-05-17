// Minimal type stub for @novnc/novnc. The library ships untyped ESM
// source; we only need the default RFB constructor.

declare module "@novnc/novnc" {
  export default class RFB {
    constructor(
      target: HTMLElement,
      url: string,
      options?: {
        credentials?: { password?: string; username?: string; target?: string };
        wsProtocols?: string[];
        shared?: boolean;
        repeaterID?: string;
      },
    );
    disconnect(): void;
    viewOnly: boolean;
    scaleViewport: boolean;
    resizeSession: boolean;
    background: string;
  }
}
