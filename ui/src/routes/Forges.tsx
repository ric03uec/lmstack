import { useMemo, useState } from 'react';
import { api, fmtWall, shortKey, type ForgeStatus, type ForgeSummary } from '../api';
import { fmtLoaded, useAsync } from '../hooks';
import { StatusBadge } from '../components/StatusBadge';

const GROUPS: { title: string; statuses: ForgeStatus[] }[] = [
  { title: 'Running', statuses: ['running'] },
  { title: 'In review', statuses: ['in-review'] },
  { title: 'Queued', statuses: ['queued'] },
  { title: 'Completed', statuses: ['merged', 'cleaned'] },
  { title: 'Failed', statuses: ['failed'] },
  { title: 'Stale', statuses: ['stale'] },
];

export function Forges() {
  const [role, setRole] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const { data, error, loading, loadedAt, reload } = useAsync(() => api.forges(), []);
  const instancesReq = useAsync(() => api.instances(), []);

  const filtered = useMemo(() => {
    if (!data) return null;
    return data.filter((f) => {
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

  return (
    <div>
      <div className="section-title">
        <span>Forges</span>
        {filtered && <span className="count">({filtered.length} shown)</span>}
        <div style={{ flex: 1 }} />
        <span className="refresh-info">{fmtLoaded(loadedAt)}</span>
        <button onClick={reload} disabled={loading}>Refresh</button>
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
          <option value="merged">merged</option>
          <option value="cleaned">cleaned</option>
          <option value="failed">failed</option>
          <option value="stale">stale</option>
        </select>
      </div>

      {error && <div className="error">error: {error}</div>}
      {filtered && filtered.length === 0 && !error && (
        <div className="empty">No forges match the current filters.</div>
      )}

      {grouped?.map((g) => (g.forges.length > 0 ? (
        <ForgeGroup key={g.title} title={g.title} forges={g.forges} />
      ) : null))}
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
            <th>shape</th>
            <th>tier</th>
            <th>host</th>
            <th>wall</th>
            <th>judge</th>
            <th>pr</th>
          </tr>
        </thead>
        <tbody>
          {forges.map((f) => (
            <tr key={f.key} onClick={() => { window.location.hash = `#/forge/${encodeURIComponent(f.key)}`; }}>
              <td><StatusBadge status={f.status} /></td>
              <td className="key">{shortKey(f.key)}</td>
              <td>{f.shape ?? '—'}</td>
              <td>{f.tier ?? '—'}</td>
              <td>{f.role}</td>
              <td className="mono">{fmtWall(f.wallMin)}</td>
              <td className="mono">{f.judgeRounds || '—'}</td>
              <td className="mono">{f.pr ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
