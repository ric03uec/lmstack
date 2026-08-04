import { useEffect, useState } from 'react';
import { Instances } from './routes/Instances';
import { Forges } from './routes/Forges';
import { ForgeDetail } from './routes/ForgeDetail';
import { Ledger } from './routes/Ledger';

type Route =
  | { name: 'instances' }
  | { name: 'forges' }
  | { name: 'forge'; key: string }
  | { name: 'ledger' };

const REPO_URL = 'https://github.com/ric03uec/lmstack';
const DOCS_URL = 'https://ric03uec.github.io/lmstack/';

function parseHash(): Route {
  const h = window.location.hash.replace(/^#\/?/, '');
  if (!h || h === 'instances') return { name: 'instances' };
  if (h === 'forges') return { name: 'forges' };
  if (h === 'ledger') return { name: 'ledger' };
  if (h.startsWith('forge/')) return { name: 'forge', key: decodeURIComponent(h.slice('forge/'.length)) };
  return { name: 'instances' };
}

export function App() {
  const [route, setRoute] = useState<Route>(parseHash());

  useEffect(() => {
    const on = () => setRoute(parseHash());
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);

  const isActive = (name: string) =>
    route.name === name || (name === 'forges' && route.name === 'forge');

  return (
    <div className="app">
      <header className="header">
        <a className="brand" href="#/instances">
          <img src="./lmstack.svg" alt="" />
          <span className="name">lmstack</span>
          <span className="tagline">put your GPUs to work</span>
        </a>
        <div className="spacer" />
        <div className="links">
          <a href={DOCS_URL} target="_blank" rel="noreferrer" title="Documentation">
            <BookIcon /> Docs
          </a>
          <a href={REPO_URL} target="_blank" rel="noreferrer" title="Source on GitHub">
            <GithubIcon /> GitHub
          </a>
        </div>
      </header>

      <aside className="sidebar">
        <nav>
          <a href="#/instances" className={isActive('instances') ? 'active' : ''}>
            <span className="icon"><ServerIcon /></span> Instances
          </a>
          <a href="#/forges" className={isActive('forges') ? 'active' : ''}>
            <span className="icon"><HammerIcon /></span> Forges
          </a>
          <a href="#/ledger" className={isActive('ledger') ? 'active' : ''}>
            <span className="icon"><BookIcon /></span> Ledger
          </a>
        </nav>
      </aside>

      <main className="main">
        {route.name === 'instances' && <Instances />}
        {route.name === 'forges' && <Forges />}
        {route.name === 'forge' && <ForgeDetail forgeKey={route.key} />}
        {route.name === 'ledger' && <Ledger />}
      </main>
    </div>
  );
}

// ── icons (inline SVG, currentColor) ─────────────────────────────────────

function GithubIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/>
    </svg>
  );
}

function BookIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M0 1.75A.75.75 0 0 1 .75 1h4.253c1.227 0 2.317.59 3 1.501A3.744 3.744 0 0 1 11.006 1h4.245a.75.75 0 0 1 .75.75v10.5a.75.75 0 0 1-.75.75h-4.507a2.25 2.25 0 0 0-1.591.659l-.622.621a.75.75 0 0 1-1.06 0l-.622-.621A2.25 2.25 0 0 0 5.258 13H.75a.75.75 0 0 1-.75-.75Zm7.251 10.324.004-5.073-.002-2.253A2.25 2.25 0 0 0 5.003 2.5H1.5v9h3.757a3.75 3.75 0 0 1 1.994.574Zm1.504-5.076v5.076a3.75 3.75 0 0 1 1.994-.574H14.5v-9h-3.495a2.25 2.25 0 0 0-2.25 2.248l-.004 2.25Z"/>
    </svg>
  );
}

function ServerIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M2 2.75C2 1.784 2.784 1 3.75 1h8.5c.966 0 1.75.784 1.75 1.75v2.5A1.75 1.75 0 0 1 12.25 7h-8.5A1.75 1.75 0 0 1 2 5.25Zm1.75-.25a.25.25 0 0 0-.25.25v2.5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25v-2.5a.25.25 0 0 0-.25-.25Zm-1.75 8c0-.966.784-1.75 1.75-1.75h8.5c.966 0 1.75.784 1.75 1.75v2.5A1.75 1.75 0 0 1 12.25 15h-8.5A1.75 1.75 0 0 1 2 13.25Zm1.75-.25a.25.25 0 0 0-.25.25v2.5c0 .138.112.25.25.25h8.5a.25.25 0 0 0 .25-.25v-2.5a.25.25 0 0 0-.25-.25ZM5 4a1 1 0 1 1-2 0 1 1 0 0 1 2 0Zm-1 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z"/>
    </svg>
  );
}

function HammerIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M9.53.22a.75.75 0 0 1 1.06 0l4.19 4.19a.75.75 0 0 1 0 1.06L13.06 7l1.03 1.03a1.75 1.75 0 0 1 0 2.48l-1.55 1.54a1.75 1.75 0 0 1-2.47 0L8 9l-6.42 6.42a.75.75 0 1 1-1.06-1.06L6.94 8 3.85 4.9a.75.75 0 0 1 0-1.06L5.4 2.29a1.75 1.75 0 0 1 2.47 0L9 3.44 9.53.22Zm-3.72 3.13a.25.25 0 0 0-.35 0L4.47 4.35 8.5 8.38l1.35-1.35Z"/>
    </svg>
  );
}
