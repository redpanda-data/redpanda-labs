# examples module

This Antora module holds runnable code for Product Docs tutorials: the
chat-room client applications, the data-transforms cookbook, the OIDC compose
stack, and similar. It is not a solution, and nothing here is gated.

How it is used:

- A Product Docs page shows a file with
  `include::solutions:examples:example$<path>[tags=<region>]`.
- Readers get the code as public attachment zips. The docs-site
  `archive-attachments` extension builds them from `attachments/` at build
  time; nothing is uploaded by hand.

Layout:

```
docs/modules/examples/
  examples/<area>/<name>/...      files shown on pages via include::example$
  attachments/<area>/<name>/...   files shipped to readers (symlinks into examples/ or real files)
```

Rules:

- No `pages/` here. This module has no landing page, no metadata, and no
  steps; `tools/check-metadata.sh` and `tools/changed-solutions.sh` skip it.
- Antora drops dotfiles and files without an extension from attachments.
  Publish `.env.example` as `env.example` and `Makefile` as `Makefile.mk`.
- Keep each example runnable on its own and name its directory after the
  Product Docs page it serves.
