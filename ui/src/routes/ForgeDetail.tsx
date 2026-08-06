import { useState, useMemo } from 'react';
import { marked } from 'marked';
import { api, fmtWall, shortKey } from '../api';
import { fmtLoaded, useAsync } from '../hooks';
import { StatusBadge } from '../components/StatusBadge';

// Configure marked once: GFM tables/task-lists, single-newline line breaks
// (LLM briefs use `\n` for paragraph breaks and expect them to render).
marked.setOptions({ gfm: true, breaks: true });

// The brief and judge rounds are written by our own tools into files under
// ~/.lmstack/ — this UI is the only reader. We trust the content and render
// it without sanitising; if a future feature ever exposes untrusted markdown
// here, add a sanitiser (e.g. DOMPurify) before this call.
function Markdown({ src }: { src: string }) {
  const html = useMemo(() => marked.parse(src) as string, [src]);
  return <div className="md" dangerouslySetInnerHTML={{ __html: html }} />;
}

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
        {run.brief ? <Markdown src={run.brief} /> : <div className="empty">no brief.md on disk</div>}
      </div>

      <div className="panel">
        <h3>Judge rounds ({run.judgeRounds.length})</h3>
        {run.judgeRounds.length === 0 && <div className="empty">(none yet)</div>}
        {run.judgeRounds.map((r) => (
          <div key={r.n} style={{ marginBottom: 16 }}>
            <div className="round-label">round {r.n}</div>
            <Markdown src={r.text} />
          </div>
        ))}
      </div>

      <LogTabs execLog={execLog} judgeLog={judgeLog} />
    </>
  );
}

function LogTabs({ execLog, judgeLog }: {
  execLog: import('../api').LogTail | null;
  judgeLog: import('../api').LogTail | null;
}) {
  const [active, setActive] = useState<'exec' | 'judge'>('exec');
  const log = active === 'exec' ? execLog : judgeLog;
  return (
    <div className="log-tabs">
      <div className="log-tabs-nav" role="tablist">
        <button
          role="tab"
          aria-selected={active === 'exec'}
          className={active === 'exec' ? 'active' : ''}
          onClick={() => setActive('exec')}
        >
          lm-exec
          {execLog?.exists && <span className="tab-count">{execLog.lines.length}</span>}
        </button>
        <button
          role="tab"
          aria-selected={active === 'judge'}
          className={active === 'judge' ? 'active' : ''}
          onClick={() => setActive('judge')}
        >
          lm-judge
          {judgeLog?.exists && <span className="tab-count">{judgeLog.lines.length}</span>}
        </button>
        <div className="log-tabs-meta">
          {log?.truncated && <span>tail · </span>}
          {log?.exists && <span className="mono">{fmtBytes(log.sizeBytes)}</span>}
        </div>
      </div>
      <LogPane log={log} />
    </div>
  );
}

function LogPane({ log }: { log: import('../api').LogTail | null }) {
  return (
    <div className="log-pane log-pane-tab">
      {!log && <div className="empty">loading…</div>}
      {log && !log.exists && <div className="empty">no log file at {log.path}</div>}
      {log && log.exists && log.lines.length === 0 && <div className="empty">(empty)</div>}
      {log && log.exists && log.lines.length > 0 && <pre>{log.lines.join('\n')}</pre>}
    </div>
  );
}

function fmtBytes(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}
