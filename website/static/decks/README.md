# Decks

Static Reveal.js decks served from the docs site. Each folder becomes a URL:

```
website/static/decks/ai-tinkerers/  →  https://ric03uec.github.io/lmstack/decks/ai-tinkerers/
```

Docusaurus copies `static/` verbatim into the build, so no config changes are needed
to add a deck — the existing `docs.yml` workflow picks it up.

## Add a new deck

```
cp -r website/static/decks/_template website/static/decks/<name>
# edit website/static/decks/<name>/slides.md
```

Preview locally by opening `website/static/decks/<name>/index.html` directly in a
browser, or run the docs site (`npm run start` in `website/`) and visit
`/decks/<name>/`.

## Authoring

Slides are Markdown separated by `---` on its own line. Speaker notes start with
`Note:` and open with `S`. The shared theme lives at `../lmstack.css` and matches
the docs site palette.

Special slide classes (add via `<!-- .slide: class="..." -->` at the top of a
slide):

- `title` — centered title layout
- `stack` — larger monospace, for stack/architecture diagrams
- `closer` — centered layout with room for a QR code

## Reveal.js keys

- `Space` / `→` — next slide
- `S` — speaker notes
- `F` — fullscreen
- `O` — overview
- `?` — full shortcut list
