import { api } from '../api';
import { fmtLoaded, useAsync } from '../hooks';

export function Instances() {
  const { data, error, loading, loadedAt, reload } = useAsync(() => api.instances(), []);

  return (
    <div>
      <div className="section-title">
        <span>Instances</span>
        {data && <span className="count">({data.length} installed)</span>}
        <div style={{ flex: 1 }} />
        <span className="refresh-info">{fmtLoaded(loadedAt)}</span>
        <button onClick={reload} disabled={loading}>Refresh</button>
      </div>

      {error && <div className="error">error: {error}</div>}
      {!error && data && data.length === 0 && (
        <div className="empty">No instances installed. Run /lmstack:install to add one.</div>
      )}
      <div className="cards">
        {data?.map((inst) => (
          <div className="card" key={inst.role}>
            <h3>{inst.role}</h3>
            <div className="row"><span>engine</span><strong>{inst.engine ?? '—'}</strong></div>
            <div className="row"><span>gpu</span><strong>{inst.gpu ?? '—'}</strong></div>
            <div className="row"><span>models</span><strong>{inst.models.length ? inst.models.join(', ') : '—'}</strong></div>
            <div className="row"><span>probe</span><strong>{inst.probeAt ?? '—'}</strong></div>
            <div className="row"><span>verdict</span><strong>{inst.verdict ?? '—'}</strong></div>
            <div className="row" style={{ marginTop: 6 }}>
              <span>forges</span>
              <strong>
                {inst.counts.running} running · {inst.counts.in_review} in-review · {inst.counts.queued} queued · {inst.counts.merged + inst.counts.cleaned} done · {inst.counts.failed} failed
              </strong>
            </div>
            <div style={{ marginTop: 8 }}>
              <a href={`#/forges`}>view forges →</a>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
