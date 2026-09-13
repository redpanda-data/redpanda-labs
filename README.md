# Redpanda Solutions

End-to-end, runnable reference architectures built on Redpanda, published at
[docs.redpanda.com/solutions](https://docs.redpanda.com/solutions/). Each
solution is a real system a reader can start with `make up`, build step by
step, and prove with `make verify`.

This repository owns the `solutions` Antora component and the code behind
every solution. It was previously `redpanda-labs`; the labs content is frozen
here until it is migrated (see below).

## Layout

```
docs/                    the solutions Antora component (descriptor, landing page, one module per solution)
docs/modules/examples/   ungated code for Product Docs tutorials (not a solution; see its README.md)
solutions/<slug>/        the code of one solution: compose stack, services, Makefile, verify script, Doc Detective specs
tools/                   shared harness: scaffolding, metadata checks, CI matrix, verify helpers, local playbook
templates/solution/      the scaffold that tools/new-solution.sh copies
.github/workflows/       ci (run changed solutions), docs (metadata, Antora build, Doc Detective, links),
                         release (bundle per published version + the Netlify build hook), nightly (latest images)
labs-docs/ and the legacy directories (docker-compose/, clients/, data-transforms/, kubernetes/,
connect-plugins/, setup-tests/)   frozen Redpanda Labs content awaiting migration
```

## Add a solution

```bash
tools/new-solution.sh <slug>          # scaffold solutions/<slug>/ and docs/modules/<slug>/
cd solutions/<slug> && make up seed verify
tools/check-metadata.sh               # the metadata contract
npm run build                         # Antora build (needs ~/.git-credentials, see CONTRIBUTING.md)
```

[CONTRIBUTING.md](CONTRIBUTING.md) is the writer guide: what qualifies as a
solution, the metadata contract, page structure, the verification bar, and
the workflow from proposal to release. Agents read [CLAUDE.md](CLAUDE.md) or
[AGENTS.md](AGENTS.md).

## How it ships

- A pull request runs `ci` (every solution it touches, end to end) and `docs`
  (metadata, a real Antora build, Doc Detective for the touched solutions, an
  offline link check).
- On merge to `main`, `release` publishes `<slug>-<version>.zip` under the
  tag `<slug>/<version>` for every `published` or `deprecated` solution whose
  authored `:page-solution-version:` has no release yet, then posts the
  Netlify build hook once. That hook call is the only site-build trigger, so
  every merge to `main` rebuilds the site.
- `nightly` runs every solution against the latest Redpanda, Console, and
  Connect images and opens an issue on failure.

## Labs content is frozen

`labs-docs/` (the `labs` Antora component) and the legacy code directories
still build and publish under `/labs/` while each lab is promoted into a
solution, extracted into Product Docs, or retired with a redirect. Do not
change them here; migrate them. The labs contributing guides are kept for
reference at `labs-docs/CONTRIBUTING.adoc` and `labs-docs/CONTRIBUTING-LABS.adoc`.

## License

[Apache License 2.0](LICENSE).
