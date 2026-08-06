import { useMemo, useState } from 'react';
import { api, fmtExecTime, shortKey } from '../api';
import { fmtLoaded, useAsync } from '../hooks';

export function Ledger() {
  const { data, error, loading, loadedAt, reload } = useAsync(() => api.ledger({ limit: 500 }), []);
  const [outcome, setOutcome] = useState('');
  const [role, setRole] = useState('');

  const outcomes = useMemo(() => uniq(data?.map((r) => r.outcome).filter((v): v is string => !!v)), [data]);
  const roles = useMemo(() => uniq(data?.map((r) => r.host_role).filter((v): v is string => !!v)), [data]);

  const filtered = useMemo(() => {
    if (!data) return null;
    return data.filter((r) => {
      if (outcome && r.outcome !== outcome) return false;
      if (role && r.host_role !== role) return false;
      return true;
    });
  }, [data, outcome, role]);

  return (
    <div>
      <div className="section-title">
        <span>History of completed tasks</span>
        {filtered && <span className="count">({filtered.length} of {data?.length ?? 0} runs)</span>}
        <div style={{ flex: 1 }} />
        <span className="refresh-info">{fmtLoaded(loadedAt)}</span>
        <button onClick={reload} disabled={loading}>Refresh</button>
      </div>

      <div className="filters">
        <label>outcome: </label>
        <select value={outcome} onChange={(e) => setOutcome(e.target.value)}>
          <option value="">all</option>
          {outcomes.map((o) => <option key={o} value={o}>{o}</option>)}
        </select>
        <label>host: </label>
        <select value={role} onChange={(e) => setRole(e.target.value)}>
          <option value="">all</option>
          {roles.map((r) => <option key={r} value={r}>{r}</option>)}
        </select>
      </div>

      {error && <div className="error">error: {error}</div>}
      {filtered && filtered.length === 0 && !error && <div className="empty">No completed tasks yet.</div>}
      {filtered && filtered.length > 0 && (
        <table className="table">
          <thead>
            <tr>
              <th>ended (UTC)</th>
              <th>key</th>
              <th>tier</th>
              <th>host</th>
              <th>outcome</th>
              <th>exec time</th>
              <th>judge</th>
              <th>pr</th>
              <th>int.</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map((r, i) => (
              <tr key={`${r.key}-${r.ts}-${i}`} onClick={() => { window.location.hash = `#/forge/${encodeURIComponent(r.key)}`; }}>
                <td className="mono">{fmtEnded(r.ended ?? r.ts)}</td>
                <td className="key">{shortKey(r.key)}</td>
                <td>{fmtTier(r.tier)}</td>
                <td>{r.host_role}</td>
                <td><OutcomeBadge outcome={r.outcome} /></td>
                <td className="mono">{fmtExecTime(r.wall_min)}</td>
                <td className="mono">{r.judge_rounds || '—'}</td>
                <td className="mono">{r.pr ?? '—'}</td>
                <td className="mono">{r.interventions ?? 0}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

function OutcomeBadge({ outcome }: { outcome: string }) {
  const cls = OUTCOME_CLASS[outcome] || 'outcome-neutral';
  return <span className={`badge ${cls}`}>{outcome}</span>;
}

const OUTCOME_CLASS: Record<string, string> = {
  'pr-opened': 'outcome-ok',
  merged: 'outcome-ok',
  cleaned: 'outcome-neutral',
  'no-change': 'outcome-neutral',
  failed: 'outcome-err',
  stale: 'outcome-warn',
};

function fmtTier(t: string | null | undefined): string {
  if (!t) return '—';
  const m = /^T\d+$/i.exec(t);
  return m ? t.toUpperCase() : '—';
}

function uniq(arr: string[] | undefined): string[] {
  if (!arr) return [];
  return Array.from(new Set(arr)).sort();
}

function fmtEnded(s: string | null | undefined): string {
  if (!s) return '—';
  return s.replace('T', ' ').replace(/\..*Z?$/, '').replace(/Z$/, '');
}
