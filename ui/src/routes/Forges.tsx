import { useMemo, useState } from 'react';
import { api, fmtExecTime, shortKey, type ForgeStatus, type ForgeSummary } from '../api';
import { fmtLoaded, useAsync } from '../hooks';
import { StatusBadge } from '../components/StatusBadge';

// Forges show only live/pre-terminal states. Anything that reached a terminal
// outcome (merged, cleaned, failed, or stale) lives on the History page.
const GROUPS: { title: string; statuses: ForgeStatus[] }[] = [
  { title: 'In progress', statuses: ['running'] },
  { title: 'Awaiting triage', statuses: ['in-review'] },
  { title: 'Queued', statuses: ['queued'] },
];
const LIVE_STATUSES: ForgeStatus[] = ['running', 'in-review', 'queued'];
const COMPLETED_OUTCOMES = new Set(['pr-opened', 'merged', 'cleaned', 'no-change']);
const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

export function Forges() {
  const [role, setRole] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const { data, error, loading, loadedAt, reload } = useAsync(() => api.forges(), []);
  const instancesReq = useAsync(() => api.instances(), []);
  const ledgerReq = useAsync(() => api.ledger({ limit: 500 }), []);

  const filtered = useMemo(() => {
    if (!data) return null;
    return data
      .filter((f) => LIVE_STATUSES.includes(f.status as ForgeStatus))
      .filter((f) => {
        if (role && f.role !== role) return false;
        if (statusFilter && f.status !== statusFilter) return false;
        return true;
      });
  }, [data, role, statusFilter]);

  const grouped = useMemo(() => {
    if (!filtered) return null;
    return GROUPS.map((g) => ({
      title: g.title,
      forges: filtered.filter((f) => g.statuses.includes(f.status as ForgeStatus)),
    }));
  }, [filtered]);

  const completed30d = useMemo(() => {
    if (!ledgerReq.data) return null;
    const cutoff = Date.now() - THIRTY_DAYS_MS;
    return ledgerReq.data.filter((r) => {
      if (!COMPLETED_OUTCOMES.has(r.outcome)) return false;
      const t = Date.parse(r.ended || r.ts || '');
      return Number.isFinite(t) && t >= cutoff;
    }).length;
  }, [ledgerReq.data]);

  return (
    <div>
      <div className="section-title">
        <span>Forges</span>
        {filtered && <span className="count">({filtered.length} live)</span>}
        <div style={{ flex: 1 }} />
        <span className="refresh-info">{fmtLoaded(loadedAt)}</span>
        <button onClick={reload} disabled={loading}>Refresh</button>
      </div>

      <div className="stats-row">
        <StatCard label="Completed (30d)" value={completed30d} hint="merged · cleaned · no-change" />
        <StatCard label="In progress" value={countStatus(filtered, 'running')} />
        <StatCard label="Awaiting triage" value={countStatus(filtered, 'in-review')} />
        <StatCard label="Queued" value={countStatus(filtered, 'queued')} />
      </div>

      <div className="filters">
        <label>host: </label>
        <select value={role} onChange={(e) => setRole(e.target.value)}>
          <option value="">all</option>
          {instancesReq.data?.map((i) => (
            <option key={i.role} value={i.role}>{i.role}</option>
          ))}
        </select>
        <label>status: </label>
        <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">all</option>
          <option value="running">running</option>
          <option value="in-review">in-review</option>
          <option value="queued">queued</option>
        </select>
      </div>

      {error && <div className="error">error: {error}</div>}
      {filtered && filtered.length === 0 && !error && (
        <div className="empty">No live forges. Completed runs are on the History page.</div>
      )}

      {grouped?.map((g) => (g.forges.length > 0 ? (
        <ForgeGroup key={g.title} title={g.title} forges={g.forges} />
      ) : null))}
    </div>
  );
}

function countStatus(forges: ForgeSummary[] | null, status: ForgeStatus): number | null {
  if (!forges) return null;
  return forges.filter((f) => f.status === status).length;
}

function StatCard({ label, value, hint }: { label: string; value: number | null; hint?: string }) {
  return (
    <div className="stat-card">
      <div className="stat-value">{value ?? '—'}</div>
      <div className="stat-label">{label}</div>
      {hint && <div className="stat-hint">{hint}</div>}
    </div>
  );
}

function ForgeGroup({ title, forges }: { title: string; forges: ForgeSummary[] }) {
  return (
    <div style={{ marginTop: 16 }}>
      <div className="section-title">
        <span>{title}</span>
        <span className="count">({forges.length})</span>
      </div>
      <table className="table">
        <thead>
          <tr>
            <th>status</th>
            <th>key</th>
            <th>tier</th>
            <th>host</th>
            <th>exec time</th>
            <th>judge</th>
            <th>pr</th>
          </tr>
        </thead>
        <tbody>
          {forges.map((f) => (
            <tr key={f.key} onClick={() => { window.location.hash = `#/forge/${encodeURIComponent(f.key)}`; }}>
              <td><StatusBadge status={f.status} /></td>
              <td className="key">{shortKey(f.key)}</td>
              <td>{fmtTier(f.tier)}</td>
              <td>{f.role}</td>
              <td className="mono">{fmtExecTime(f.wallMin)}</td>
              <td className="mono">{f.judgeRounds || '—'}</td>
              <td className="mono">{f.pr ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// Only surface Tn labels (T1/T2/T3/…). Non-tier values like "park" are user
// annotations that don't belong in a tier column.
function fmtTier(t: string | null | undefined): string {
  if (!t) return '—';
  const m = /^T\d+$/i.exec(t);
  return m ? t.toUpperCase() : '—';
}
