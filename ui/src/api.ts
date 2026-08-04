export type ForgeStatus =
  | 'queued'
  | 'running'
  | 'in-review'
  | 'merged'
  | 'failed'
  | 'cleaned'
  | 'stale';

export interface Instance {
  role: string;
  host?: string;
  engine?: string;
  gpu?: string;
  models: string[];
  probeAt?: string;
  verdict?: string;
  counts: { running: number; in_review: number; queued: number; merged: number; failed: number; cleaned: number; stale: number };
}

export interface ForgeSummary {
  key: string;
  role: string;
  status: ForgeStatus;
  tier?: string;
  shape?: string;
  pr?: string;
  wallMin?: number | null;
  startedAt?: string | null;
  judgeRounds: number;
  title?: string;
  url?: string;
}

export interface JudgeRound { n: number; text: string; }

export interface ForgeDetail {
  task: Record<string, unknown> & { key: string; status?: string; url?: string; title?: string };
  run: {
    exists: boolean;
    brief: string | null;
    judgeRounds: JudgeRound[];
    startedAt: string | null;
    endedAt: string | null;
    tmuxAlive: boolean;
    worktreePath: string | null;
    worktreeExists: boolean;
    branch: string | null;
  };
  ledger: Record<string, unknown> | null;
  role: string;
  slug: string;
}

export interface LogTail {
  lines: string[];
  sizeBytes: number;
  truncated: boolean;
  exists: boolean;
  path: string;
}

export interface LedgerRecord {
  key: string;
  host_role: string;
  tier: string | null;
  shape: string | null;
  judge_rounds: number;
  outcome: string;
  pr: string | null;
  started: string | null;
  ended: string | null;
  wall_min: number | null;
  interventions: number;
  ts: string;
}

async function j<T>(path: string): Promise<T> {
  const r = await fetch(path);
  if (!r.ok) throw new Error(`${path} → ${r.status}`);
  return r.json();
}

export const api = {
  instances: () => j<Instance[]>('/api/instances'),
  instance: (role: string) => j<Record<string, unknown>>(`/api/instances/${encodeURIComponent(role)}`),
  forges: (params: { role?: string; status?: string } = {}) => {
    const qs = new URLSearchParams();
    if (params.role) qs.set('role', params.role);
    if (params.status) qs.set('status', params.status);
    const q = qs.toString();
    return j<ForgeSummary[]>('/api/forges' + (q ? '?' + q : ''));
  },
  forge: (key: string) => j<ForgeDetail>(`/api/forges/${encodeURIComponent(key)}`),
  log: (key: string, which: 'exec' | 'judge', tail = 200) =>
    j<LogTail>(`/api/forges/${encodeURIComponent(key)}/log/${which}?tail=${tail}`),
  ledger: (params: { limit?: number; shape?: string; outcome?: string; role?: string } = {}) => {
    const qs = new URLSearchParams();
    if (params.limit) qs.set('limit', String(params.limit));
    if (params.shape) qs.set('shape', params.shape);
    if (params.outcome) qs.set('outcome', params.outcome);
    if (params.role) qs.set('role', params.role);
    const q = qs.toString();
    return j<LedgerRecord[]>('/api/ledger' + (q ? '?' + q : ''));
  },
};

export function fmtWall(min: number | null | undefined): string {
  if (min == null) return '—';
  if (min < 60) return `${min}m`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${h}h${m ? ` ${m}m` : ''}`;
}

export function shortKey(key: string): string {
  // owner__repo#num → owner/repo#num
  return key.replace('__', '/');
}
