import type { ReactNode } from 'react';
import { api, type Instance } from '../api';
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
        <div className="empty">No instances installed. Run <code>/lmstack:install</code> to add one.</div>
      )}

      <div className="inst-list">
        {data?.map((inst) => <InstanceCard key={inst.role} inst={inst} />)}
      </div>
    </div>
  );
}

function InstanceCard({ inst }: { inst: Instance }) {
  const total = inst.counts.running + inst.counts.in_review + inst.counts.queued
    + inst.counts.merged + inst.counts.failed + inst.counts.cleaned + inst.counts.stale;
  const missing = [
    !inst.sources.hostYaml && 'host.yml',
    !inst.sources.probeJson && 'probe.json',
    !inst.sources.classifyJson && 'classify.json',
  ].filter(Boolean) as string[];

  return (
    <section className="inst">
      <header className="inst-hdr">
        <VendorLogo vendor={inst.gpu?.vendor ?? null} />
        <div className="inst-hdr-main">
          <h2>{inst.role}</h2>
          <div className="inst-sub">
            {inst.gpu?.model ? <span>{inst.gpu.model}</span> : <span className="muted">unknown GPU</span>}
            {inst.engine.kind && <span className="dot">·</span>}
            {inst.engine.kind && <span>{prettyEngine(inst.engine.kind)}</span>}
            {inst.connection && <span className="dot">·</span>}
            {inst.connection && <span>{inst.connection === 'local' ? 'localhost' : inst.connection}</span>}
          </div>
        </div>
        <div className="inst-hdr-status">
          {inst.verdict && <span className={`badge verdict-${inst.verdict}`}>{inst.verdict}</span>}
          <a href="#/forges" className="btn-link">view {total} forge{total === 1 ? '' : 's'} →</a>
        </div>
      </header>

      {missing.length > 0 && (
        <div className="inst-hint">
          Missing on disk: {missing.map((m) => <code key={m}>{m}</code>).reduce<ReactNode[]>((acc, el, i) => (i === 0 ? [el] : [...acc, ', ', el]), [])}.
          {' '}Run <code>/lmstack:analyze {inst.connection || '<target>'}</code> to populate hardware & engine details.
        </div>
      )}

      <div className="inst-grid">
        <Section title="Hardware">
          <Row k="GPU"      v={inst.gpu?.model} />
          <Row k="VRAM"     v={fmtGib(inst.gpu?.vramGib)} />
          <Row k="GTT"      v={fmtGib(inst.gpu?.gttGib)} />
          <Row k="Driver"   v={inst.gpu?.driver} />
          <Row k="System RAM" v={fmtGib(inst.memory?.totalGib)} />
        </Section>

        <Section title="Inference engine">
          <Row k="Engine"    v={prettyEngine(inst.engine.kind)} />
          <Row k="Role"      v={inst.engine.host || inst.role} />
          <Row k="Reason"    v={inst.engine.reason} />
          <Row k="Docker"    v={fmtDocker(inst.docker)} />
          <Row k="Runtimes"  v={inst.docker?.runtimes.join(', ') || null} />
          <Row k="Vulkan"    v={inst.vulkan ? (inst.vulkan.present ? (inst.vulkan.device || 'yes') : 'no') : null} />
        </Section>

        <Section title="Operating system">
          <Row k="OS"      v={inst.os?.pretty} />
          <Row k="Kernel"  v={inst.os?.kernel} />
          <Row k="Arch"    v={inst.os?.arch} />
          <Row k="Installed" v={inst.installedAt} />
        </Section>

        <Section title="Forge activity">
          <Row k="Running"   v={inst.counts.running} />
          <Row k="In review" v={inst.counts.in_review} />
          <Row k="Queued"    v={inst.counts.queued} />
          <Row k="Merged"    v={inst.counts.merged} />
          <Row k="Cleaned"   v={inst.counts.cleaned} />
          <Row k="Failed"    v={inst.counts.failed} />
          {inst.counts.stale > 0 && <Row k="Stale" v={inst.counts.stale} />}
        </Section>
      </div>

      {inst.models.length > 0 && (
        <div className="inst-models">
          <h3>Models</h3>
          <table className="table dense">
            <thead>
              <tr>
                <th>slug</th>
                <th>hf model</th>
                <th>context</th>
                <th>max seqs</th>
                <th>VRAM est.</th>
                <th>port</th>
                <th>tier</th>
                <th>active</th>
              </tr>
            </thead>
            <tbody>
              {inst.models.map((m) => (
                <tr key={m.slug ?? String(Math.random())}>
                  <td className="mono">{m.slug ?? '—'}</td>
                  <td className="mono">{m.hfModel ?? '—'}</td>
                  <td className="mono">{fmtCtx(m.contextTokens)}</td>
                  <td className="mono">{m.maxNumSeqs ?? '—'}</td>
                  <td className="mono">{fmtGib(m.vramEstimateGib)}</td>
                  <td className="mono">{m.port ?? '—'}</td>
                  <td className="mono">{m.tier ?? '—'}</td>
                  <td>{m.active ? <span className="badge merged">active</span> : <span className="badge cleaned">idle</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {(inst.arithmetic.length > 0 || inst.warnings.length > 0) && (
        <div className="inst-extra">
          {inst.arithmetic.length > 0 && (
            <div className="inst-extra-block">
              <h3>Memory arithmetic</h3>
              <pre>{inst.arithmetic.join('\n')}</pre>
            </div>
          )}
          {inst.warnings.length > 0 && (
            <div className="inst-extra-block">
              <h3>Warnings</h3>
              <ul>{inst.warnings.map((w, i) => <li key={i}>{w}</li>)}</ul>
            </div>
          )}
        </div>
      )}
    </section>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="inst-sec">
      <h3>{title}</h3>
      <dl>{children}</dl>
    </div>
  );
}

function Row({ k, v }: { k: string; v: ReactNode | number | null | undefined }) {
  const empty = v == null || v === '' || v === undefined;
  return (
    <>
      <dt>{k}</dt>
      <dd className={empty ? 'muted' : ''}>{empty ? '—' : v}</dd>
    </>
  );
}

function VendorLogo({ vendor }: { vendor: string | null }) {
  const v = (vendor || '').toLowerCase();
  if (v === 'nvidia') {
    return (
      <div className="vendor vendor-nvidia" aria-label="NVIDIA">
        <NvidiaMark />
        <span>NVIDIA</span>
      </div>
    );
  }
  if (v === 'amd') {
    return (
      <div className="vendor vendor-amd" aria-label="AMD">
        <AmdMark />
        <span>AMD</span>
      </div>
    );
  }
  return (
    <div className="vendor vendor-generic" aria-label="GPU">
      <GpuMark />
      <span>GPU</span>
    </div>
  );
}

// Simple stylised marks — deliberately not reproducing the trademarked
// wordmarks. A large monogram in the vendor's brand hue plus a plain label.
function NvidiaMark() {
  return (
    <svg viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <rect width="48" height="48" rx="10" fill="#76b900"/>
      <text x="24" y="33" textAnchor="middle" fontFamily="Inter, Arial, sans-serif" fontWeight="800" fontSize="26" fill="#ffffff">N</text>
    </svg>
  );
}
function AmdMark() {
  return (
    <svg viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <rect width="48" height="48" rx="10" fill="#ed1c24"/>
      <text x="24" y="33" textAnchor="middle" fontFamily="Inter, Arial, sans-serif" fontWeight="800" fontSize="26" fill="#ffffff">A</text>
    </svg>
  );
}
function GpuMark() {
  return (
    <svg viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <rect width="48" height="48" rx="10" fill="#656d76"/>
      <text x="24" y="33" textAnchor="middle" fontFamily="Inter, Arial, sans-serif" fontWeight="800" fontSize="18" fill="#ffffff">GPU</text>
    </svg>
  );
}

function fmtGib(g: number | null | undefined): string | null {
  if (g == null) return null;
  return `${g} GiB`;
}
function fmtCtx(t: number | null | undefined): string {
  if (t == null) return '—';
  if (t >= 1024) return `${(t / 1024).toFixed(t % 1024 === 0 ? 0 : 1)}K`;
  return String(t);
}
function fmtDocker(d: Instance['docker']): string | null {
  if (!d) return null;
  if (!d.present) return 'not installed';
  if (!d.usable) return `${d.version ?? 'present'} (not usable)`;
  return d.version || 'usable';
}
function prettyEngine(k: string | null | undefined): string | null {
  if (!k) return null;
  const m: Record<string, string> = { vllm: 'vLLM', llamacpp: 'llama.cpp' };
  return m[k] ?? k;
}
