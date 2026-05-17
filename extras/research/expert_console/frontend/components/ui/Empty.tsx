import { cn } from "@/lib/cn";
import { ReactNode } from "react";

export function Empty({
  icon,
  title,
  hint,
  className,
}: {
  icon?: ReactNode;
  title: string;
  hint?: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "flex flex-col items-center justify-center text-center gap-3 py-12 px-6 text-fg/70",
        className,
      )}
    >
      {icon && <div className="text-accent/80">{icon}</div>}
      <div className="font-display text-base text-fg">{title}</div>
      {hint && <p className="text-sm text-muted max-w-md leading-relaxed">{hint}</p>}
    </div>
  );
}
