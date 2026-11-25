'use client';

import { use, useId, useSyncExternalStore } from 'react';

export function Mermaid({ chart }: { chart: string }) {
  // `false` on the server and during hydration
  const isClient = useSyncExternalStore(
    () => () => {},
    () => true,
    () => false,
  );

  if (!isClient) return;
  return <MermaidContent chart={chart} />;
}

const cache = new Map<string, Promise<unknown>>();

function cachePromise<T>(key: string, setPromise: () => Promise<T>): Promise<T> {
  const cached = cache.get(key);
  if (cached) return cached as Promise<T>;

  const promise = setPromise();
  cache.set(key, promise);
  return promise;
}

function MermaidContent({ chart }: { chart: string }) {
  const id = useId();
  const { default: mermaid } = use(cachePromise('mermaid', () => import('mermaid')));

  // The docs are dark only, so the theme is fixed to Nan's colours and never follows a class on the page.
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    fontFamily: 'inherit',
    themeCSS: 'margin: 1.5rem auto 0;',
    theme: 'base',
    themeVariables: {
      background: '#06080b',
      primaryColor: '#0b1118',
      primaryTextColor: '#f2eee6',
      primaryBorderColor: '#979da6',
      secondaryColor: '#0b1118',
      tertiaryColor: '#0b1118',
      lineColor: '#979da6',
      textColor: '#f2eee6',
      fontFamily: 'inherit',
    },
  });

  const { svg, bindFunctions } = use(
    cachePromise(chart, () => {
      return mermaid.render(id, chart.replaceAll('\n', '\n'));
    }),
  );

  return (
    <div
      ref={(container) => {
        if (container) bindFunctions?.(container);
      }}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}
