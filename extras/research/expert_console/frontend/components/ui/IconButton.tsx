import { cn } from "@/lib/cn";
import { forwardRef } from "react";

export const IconButton = forwardRef<
  HTMLButtonElement,
  React.ButtonHTMLAttributes<HTMLButtonElement> & { tone?: "default" | "accent" | "danger" }
>(({ className, tone = "default", children, ...props }, ref) => {
  const toneClass =
    tone === "accent"
      ? "text-accent hover:bg-accent-soft"
      : tone === "danger"
      ? "text-danger hover:bg-danger/10"
      : "text-fg/70 hover:text-fg hover:bg-elevated";
  return (
    <button
      ref={ref}
      className={cn(
        "inline-flex items-center justify-center h-8 w-8 rounded-md transition-colors",
        toneClass,
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
});
IconButton.displayName = "IconButton";
