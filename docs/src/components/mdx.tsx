import defaultMdxComponents from 'fumadocs-ui/mdx';
import type { MDXComponents } from 'mdx/types';
import {
  Bot,
  Box,
  ChartBar,
  Code,
  Cpu,
  Download,
  FlaskConical,
  FolderOpen,
  Network,
  Play,
  Settings,
  Terminal,
  Zap,
} from 'lucide-react';

export function getMDXComponents(components?: MDXComponents) {
  return {
    ...defaultMdxComponents,
    Bot,
    Box,
    ChartBar,
    Code,
    Cpu,
    Download,
    FlaskConical,
    FolderOpen,
    Network,
    Play,
    Settings,
    Terminal,
    Zap,
    ...components,
  } satisfies MDXComponents;
}

export const useMDXComponents = getMDXComponents;

declare global {
  type MDXProvidedComponents = ReturnType<typeof getMDXComponents>;
}
