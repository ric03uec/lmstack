import type { ForgeStatus } from '../api';

const LABEL: Record<ForgeStatus, string> = {
  queued: '○ queued',
  running: '● running',
  'in-review': '◐ in-review',
  merged: '✓ merged',
  failed: '✗ failed',
  cleaned: '· cleaned',
  stale: '! stale',
};

export function StatusBadge({ status }: { status: ForgeStatus | string }) {
  const key = (status as ForgeStatus) in LABEL ? (status as ForgeStatus) : ('queued' as ForgeStatus);
  return <span className={`badge ${key}`}>{LABEL[key] ?? status}</span>;
}
