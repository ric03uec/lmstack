import { api, fmtWall, shortKey } from '../api';
import { fmtLoaded, useAsync } from '../hooks';
import { StatusBadge } from '../components/StatusBadge';

export function ForgeDetail({ forgeKey }: { forgeKey: string }) {
  const detail = useAsync(() => api.forge(forgeKey), [forgeKey]);
  const execLog = useAsync(() => api.log(forgeKey, 'exec', 200), [forgeKey]);
  const judgeLog = useAsync(() => api.log(forgeKey, 'judge', 200), [forgeKey]);

  const refreshAll = () => {
    detail.reload();
    execLog.reload();
    judgeLog.reload();
  };

  const loading = detail.loading || execLog.loading || judgeLog.loading;

  return (
    <div>
      <div className="section-title">
        <a href="#/forges">← forges</a>
        <div style={{ flex: 1 }} />
        <span className="refresh-info">{fmtLoaded(detail.loadedAt)}</span>
        <button onClick={refreshAll} disabled={loading}>Refresh</button>
      </div>

      {detail.error && <div className="error">error: {detail.error}</div>}
      {detail.data && <Detail data={detail.data} execLog={execLog.data} judgeLog={judgeLog.data} />}
    </div>
  );
}

function Detail({ data, execLog, judgeLog }: {
  data: import('../api').ForgeDetail;
  execLog: import('../api').LogTail | null;
  judgeLog: import('../api').LogTail | null;
}) {
  const { task, run, ledger } = data;
  const status = (task.status as string) ?? 'queued';
  const url = task.url as string | undefined;
  const pr = (task as { pr?: string }).pr;
  const tier = (task as { tier?: string }).tier;
  const shape = (task as { shape?: string }).shape;

  return (
    <>
      <div className="detail-header">
        <span className="title">{shortKey(data.task.key)}</span>
        <StatusBadge status={status} />
        {url && <a href={url} target="_blank" rel="noreferrer">↗ issue</a>}
        {pr && <a href={pr} target="_blank" rel="noreferrer">↗ pr</a>}
      </div>

      <div className="detail-meta">
        <span className="k">host</span><span className="v">{data.role}</span>
        <span className="k">shape</span><span className="v">{shape ?? '—'}</span>
        <span className="k">tier</span><span className="v">{tier ?? '—'}</span>
        <span className="k">title</span><span className="v" style={{ fontFamily: 'inherit' }}>{(task.title as string) ?? '—'}</span>
        <span className="k">started</span><span className="v">{run.startedAt ?? '—'}</span>
        <span className="k">ended</span><span className="v">{run.endedAt ?? '—'}</span>
        <span className="k">tmux session</span><span className="v">lmstack-{data.slug} {run.tmuxAlive ? '(alive ✓)' : '(not running)'}</span>
        <span className="k">worktree</span><span className="v">{run.worktreePath ?? '—'} {run.worktreePath ? (run.worktreeExists ? '' : '(missing)') : ''}</span>
        <span className="k">branch</span><span className="v">{run.branch ?? '—'}</span>
        {ledger && (
          <>
            <span className="k">outcome</span><span className="v">{String(ledger.outcome ?? '—')} · wall {fmtWall(ledger.wall_min as number | null)} · interventions {String(ledger.interventions ?? 0)}</span>
          </>
        )}
      </div>

      <div className="panel">
        <h3>Brief</h3>
        {run.brief ? <pre>{run.brief}</pre> : <div className="empty">no brief.md on disk</div>}
      </div>

      <div className="panel">
        <h3>Judge rounds ({run.judgeRounds.length})</h3>
        {run.judgeRounds.length === 0 && <div className="empty">(none yet)</div>}
        {run.judgeRounds.map((r) => (
          <div key={r.n} style={{ marginBottom: 12 }}>
            <div style={{ color: 'var(--muted)', fontSize: 12, marginBottom: 4 }}>round {r.n}</div>
            <pre>{r.text}</pre>
          </div>
        ))}
      </div>

      <div className="logs">
        <LogPane title="lm-exec" log={execLog} />
        <LogPane title="lm-judge" log={judgeLog} />
      </div>
    </>
  );
}

function LogPane({ title, log }: { title: string; log: import('../api').LogTail | null }) {
  return (
    <div className="log-pane">
      <h4>{title}{log?.truncated ? ' — tail' : ''}</h4>
      {!log && <div className="empty">loading…</div>}
      {log && !log.exists && <div className="empty">no log file at {log.path}</div>}
      {log && log.exists && log.lines.length === 0 && <div className="empty">(empty)</div>}
      {log && log.exists && log.lines.length > 0 && <pre>{log.lines.join('\n')}</pre>}
    </div>
  );
}
