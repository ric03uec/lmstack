import { useState, type ReactNode } from 'react';
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
  // Only surface a loud hint when the *critical* file is missing (probe.json).
  // If host.yml or classify.json alone are absent the card still has useful
  // hardware/model info — a big yellow banner over that is noise.
  const missing = inst.sources.probeJson
    ? []
    : ([
        !inst.sources.hostYaml && 'host.yml',
        !inst.sources.probeJson && 'probe.json',
        !inst.sources.classifyJson && 'classify.json',
      ].filter(Boolean) as string[]);

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
          <Row k="Host / IP" v={inst.connection || (inst.sources.probeJson ? 'unknown' : null)} />
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

// Vendor marks: prefer a real logo file at /vendor/<slug>.svg (drop the
// official SVG from the vendor's press kit into ui/public/vendor/ and it
// takes over — nothing to change in this file). Fall back to a stylised
// geometric mark when the file is not there, so a fresh checkout still shows
// something the user recognises.
//
// Falling back to a big letter — the previous behaviour, "a big N" and "a big
// A" — read as a placeholder rather than a badge, which is what motivated the
// rewrite. A geometric mark reads as intentional even before the official
// file is added.
function VendorLogo({ vendor }: { vendor: string | null }) {
  const v = (vendor || '').toLowerCase();
  const spec = VENDOR_MARKS[v] || VENDOR_MARKS._generic;
  return (
    <div className={`vendor vendor-${v || 'generic'}`} aria-label={spec.label}>
      <VendorMark slug={v} spec={spec} />
      <span>{spec.label}</span>
    </div>
  );
}

type MarkSpec = { label: string; color: string; fallback: JSX.Element };

const VENDOR_MARKS: Record<string, MarkSpec> = {
  nvidia:   { label: 'NVIDIA', color: '#76B900', fallback: <NvidiaMark /> },
  amd:      { label: 'AMD',    color: '#000000', fallback: <AmdMark /> },
  _generic: { label: 'GPU',    color: '#656D76', fallback: <GpuMark /> },
};

function VendorMark({ slug, spec }: { slug: string; spec: MarkSpec }) {
  const [failed, setFailed] = useState(false);
  if (!slug || slug === '_generic' || failed) return spec.fallback;
  // The <img> onError fires when the file is missing, so the fallback SVG
  // still renders — no 404 in the console for the common "no override" case
  // once the error has been caught.
  return (
    <img
      src={`/vendor/${slug}.svg`}
      alt=""
      width={48}
      height={48}
      style={{ borderRadius: 10, background: spec.color }}
      onError={() => setFailed(true)}
    />
  );
}

// Stylised marks, used until ui/public/vendor/<slug>.svg is dropped in. Not
// the trademarked wordmarks — an eye-shaped lens for NVIDIA, a chevroned "A"
// on black for AMD, a card silhouette for the generic case.
function NvidiaMark() {
  return (
    <svg viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <rect width="48" height="48" rx="10" fill="#76B900"/>
      <path d="M8 24 C 14 15, 22 13, 28 15 C 36 17, 42 21, 42 24 C 42 27, 36 31, 28 33 C 22 35, 14 33, 8 24 Z" fill="#FFFFFF"/>
      <path d="M15 24 C 19 19, 24 18, 28 19 C 33 20, 37 22, 37 24 C 37 26, 33 28, 28 29 C 24 30, 19 29, 15 24 Z" fill="#76B900"/>
    </svg>
  );
}
function AmdMark() {
  return (
    <svg viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <rect width="48" height="48" rx="10" fill="#000000"/>
      <path d="M24 10 L 40 40 L 32 40 L 29 34 L 19 34 L 16 40 L 8 40 Z" fill="#FFFFFF"/>
      <path d="M21 30 L 27 30 L 24 22 Z" fill="#000000"/>
    </svg>
  );
}
function GpuMark() {
  return (
    <svg viewBox="0 0 48 48" fill="none" aria-hidden="true">
      <rect width="48" height="48" rx="10" fill="#656D76"/>
      <rect x="10" y="18" width="28" height="14" rx="2" fill="#FFFFFF"/>
      <rect x="14" y="22" width="6" height="6" fill="#656D76"/>
      <rect x="28" y="22" width="6" height="6" fill="#656D76"/>
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
