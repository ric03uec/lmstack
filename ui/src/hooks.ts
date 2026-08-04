import { useCallback, useEffect, useState } from 'react';

export interface Loadable<T> {
  data: T | null;
  error: string | null;
  loading: boolean;
  loadedAt: Date | null;
  reload: () => void;
}

export function useAsync<T>(fn: () => Promise<T>, deps: unknown[] = []): Loadable<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadedAt, setLoadedAt] = useState<Date | null>(null);
  const [tick, setTick] = useState(0);

  const reload = useCallback(() => setTick((t) => t + 1), []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fn()
      .then((v) => {
        if (cancelled) return;
        setData(v);
        setError(null);
        setLoadedAt(new Date());
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        setError(e instanceof Error ? e.message : String(e));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick]);

  return { data, error, loading, loadedAt, reload };
}

export function fmtLoaded(loadedAt: Date | null): string {
  if (!loadedAt) return '';
  return `loaded ${loadedAt.toLocaleTimeString()}`;
}
