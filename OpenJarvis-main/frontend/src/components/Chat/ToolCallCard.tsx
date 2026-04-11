import { useState } from 'react';
import { ChevronDown, ChevronRight, Wrench, Loader2, CheckCircle2, XCircle } from 'lucide-react';
import type { ToolCallInfo } from '../../types';

interface Props {
  toolCall: ToolCallInfo;
}

const statusConfig = {
  running: { icon: Loader2, label: 'Running', color: 'var(--color-accent)' },
  success: { icon: CheckCircle2, label: 'Done', color: 'var(--color-success)' },
  error: { icon: XCircle, label: 'Failed', color: 'var(--color-error)' },
};

export function ToolCallCard({ toolCall }: Props) {
  const [expanded, setExpanded] = useState(false);
  const config = statusConfig[toolCall.status];
  const StatusIcon = config.icon;

  return (
    <div
      className="rounded-lg text-sm overflow-hidden"
      style={{ border: '1px solid var(--color-border)', background: 'var(--color-bg-secondary)' }}
    >
      <button
        onClick={() => setExpanded(!expanded)}
        className="flex items-center gap-2 w-full px-3 py-2 transition-colors cursor-pointer"
        onMouseEnter={(e) => (e.currentTarget.style.background = 'var(--color-bg-tertiary)')}
        onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
      >
        {expanded ? (
          <ChevronDown size={14} style={{ color: 'var(--color-text-tertiary)' }} />
        ) : (
          <ChevronRight size={14} style={{ color: 'var(--color-text-tertiary)' }} />
        )}
        <Wrench size={14} style={{ color: 'var(--color-text-tertiary)' }} />
        <span style={{ color: 'var(--color-text)' }} className="font-medium">
          {toolCall.tool}
        </span>
        <div className="flex-1" />
        <StatusIcon
          size={14}
          style={{ color: config.color }}
          className={toolCall.status === 'running' ? 'animate-spin' : ''}
        />
        {toolCall.latency != null && (
          <span className="text-[11px] font-mono" style={{ color: 'var(--color-text-tertiary)' }}>
            {toolCall.latency < 1000
              ? `${Math.round(toolCall.latency)}ms`
              : `${(toolCall.latency / 1000).toFixed(1)}s`}
          </span>
        )}
      </button>
      {expanded && (
        <div className="px-3 pb-3" style={{ borderTop: '1px solid var(--color-border)' }}>
          {toolCall.arguments && (
            <div className="mt-2">
              <div className="text-[11px] font-medium mb-1" style={{ color: 'var(--color-text-tertiary)' }}>
                Arguments
              </div>
              <pre
                className="text-xs p-2 rounded overflow-x-auto font-mono"
                style={{ background: 'var(--color-code-bg)', color: 'var(--color-text-secondary)' }}
              >
                {toolCall.arguments}
              </pre>
            </div>
          )}
          {toolCall.result && (
            <div className="mt-2">
              <div className="text-[11px] font-medium mb-1" style={{ color: 'var(--color-text-tertiary)' }}>
                Result
              </div>
              <pre
                className="text-xs p-2 rounded overflow-x-auto font-mono max-h-48"
                style={{ background: 'var(--color-code-bg)', color: 'var(--color-text-secondary)' }}
              >
                {toolCall.result}
              </pre>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
