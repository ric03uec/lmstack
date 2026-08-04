// Renders a large, obvious "copy this prompt" block at the top of install.md.
// The point is that a reader who lands on that page from a talk or a link
// should be one click and one paste away from starting the install — no
// hunting through the page for the right sentence to select.
//
// The prompt is passed as children so the source stays greppable in Markdown.

import React, { useState } from 'react';
import styles from './styles.module.css';

interface Props {
  children: React.ReactNode;
  label?: string;
}

function extractText(node: React.ReactNode): string {
  if (node == null || node === false) return '';
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (Array.isArray(node)) return node.map(extractText).join('');
  if (React.isValidElement(node)) {
    const props = node.props as { children?: React.ReactNode };
    return extractText(props.children);
  }
  return '';
}

export default function CopyPrompt({ children, label = 'Copy this prompt' }: Props): React.JSX.Element {
  const text = extractText(children).trim();
  const [copied, setCopied] = useState(false);

  const onCopy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      // Clipboard blocked (insecure origin, permissions). Fall through — the
      // user can still select the text by hand, which is why it is visible.
    }
  };

  return (
    <div className={styles.wrap}>
      <div className={styles.label}>{label}</div>
      <pre className={styles.prompt}>{text}</pre>
      <button type="button" onClick={onCopy} className={styles.button}>
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  );
}
