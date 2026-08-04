import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// Docs-only site: routeBasePath '/' puts intro.md on the landing page instead
// of a marketing splash nobody maintains. The blog is off for the same reason.
//
// onBrokenLinks stays at 'throw'. The docs cross-reference heavily and a dead
// link in a setup guide costs someone an hour.

const config: Config = {
  title: 'lmstack',
  tagline: 'Put your GPU to use.',
  favicon: 'img/favicon.svg',

  url: 'https://ric03uec.github.io',
  baseUrl: '/lmstack/',
  organizationName: 'ric03uec',
  projectName: 'lmstack',
  trailingSlash: false,

  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/ric03uec/lmstack/tree/main/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    colorMode: {
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'lmstack',
      items: [
        { type: 'docSidebar', sidebarId: 'docs', position: 'left', label: 'Docs' },
        { to: '/quickstart', label: 'Quickstart', position: 'left' },
        {
          href: 'https://github.com/ric03uec/lmstack',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Start here',
          items: [
            { label: 'Introduction', to: '/' },
            { label: 'Quickstart', to: '/quickstart' },
            { label: 'The skill', to: '/skill' },
          ],
        },
        {
          title: 'Running it',
          items: [
            { label: 'Troubleshooting', to: '/operations/troubleshooting' },
            { label: 'Make targets', to: '/reference/make-targets' },
            { label: 'Roadmap', to: '/reference/roadmap' },
          ],
        },
        {
          title: 'Source',
          items: [{ label: 'GitHub', href: 'https://github.com/ric03uec/lmstack' }],
        },
      ],
    },
    prism: {
      additionalLanguages: ['bash', 'ini', 'json', 'yaml', 'docker'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
