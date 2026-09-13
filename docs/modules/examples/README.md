# examples module

This Antora module holds runnable code for Product Docs tutorials. It is not a
solution and nothing here is gated: readers get every file as a public
attachment.

How it is used:

- A Product Docs page shows a file with
  `include::solutions:examples:example$<path>[tags=<region>]`.
- Readers download single files with
  `xref:solutions:examples:attachment$<path>[]`, or the whole example as an
  archive that the docs-site `archive-attachments` extension builds from
  `attachments/` at build time. Nothing is uploaded by hand.

Layout:

```
docs/modules/examples/
  examples/<area>/<name>/...        files shown on pages via include::example$
  attachments/<area>/<name>/...     the same files, as relative symlinks, published to readers
  tests/doc-detective/              standalone Doc Detective specs for the examples
```

Rules:

- No `pages/` here. This module has no landing page, no metadata, and no
  steps; `tools/check-metadata.sh` and `tools/changed-solutions.sh` skip it.
- Antora drops dotfiles and files without an extension from attachments.
  `.env.example` is linked as `env.example`; scripts carry a `.sh` suffix;
  `conf/bootstrap.yaml` is mounted into the container as `.bootstrap.yaml`.
- Keep each example runnable on its own and name its directory after the
  Product Docs page it serves.
- Connection settings come from environment variables
  (`REDPANDA_BROKERS`, `REDPANDA_SASL_USERNAME`, `REDPANDA_SASL_PASSWORD`,
  `REDPANDA_SASL_MECHANISM`), so one code base serves the Self-Managed and
  the Redpanda Cloud variant of a page.

## Examples

| Example | Source lab | Docs page |
|---|---|---|
| `clients/chat-room/go` | `clients/chat-room/docker/go` + `clients/chat-room/cloud/go` | `streaming:develop:client-tutorials/chat-room.adoc` (and the cloud-docs stub) |
| `clients/chat-room/java` | `clients/chat-room/docker/java` + `clients/chat-room/cloud/java` | same |
| `clients/chat-room/nodejs` | `clients/chat-room/docker/nodejs` + `clients/chat-room/cloud/nodejs` (ported from kafkajs to `@confluentinc/kafka-javascript`) | same |
| `clients/chat-room/python` | `clients/chat-room/docker/python` + `clients/chat-room/cloud/python` | same |
| `clients/chat-room/rust` | `clients/chat-room/docker/rust` + `clients/chat-room/cloud/rust` | same |
| `data-transforms/go/flatten` | `data-transforms/go/flatten` | `streaming:develop:data-transforms/examples.adoc#flatten` |
| `data-transforms/go/iss_demo` | `data-transforms/go/iss_demo` | `streaming:develop:data-transforms/examples.adoc#json-to-avro` |
| `data-transforms/go/redaction` | `data-transforms/go/redaction` | `streaming:develop:data-transforms/examples.adoc#redact-pii` |
| `data-transforms/go/regex` | `data-transforms/go/regex` | `streaming:develop:data-transforms/examples.adoc#filter-with-regex` |
| `data-transforms/rust/ts-converter` | `data-transforms/rust/ts-converter` | `streaming:develop:data-transforms/examples.adoc#convert-timestamps-rust` |
| `data-transforms/rust/jq` | `data-transforms/rust/jq` | `streaming:develop:data-transforms/examples.adoc#transform-with-jq-rust` |
| `data-transforms/go/to_avro` | `data-transforms/go/to_avro` | `streaming:develop:data-transforms/examples.adoc#csv-to-avro` |
| `security/oidc-entra` | `docker-compose/oidc` | `streaming:manage:security/oidc-azure-entra.adoc` |

The `docker-compose/{single-broker,three-brokers,owl-shop}` labs moved to the
docs repo directly (`modules/get-started/attachments/docker-compose/`) because
they are compose files with no application code. `clients/stock-market-activity`
was retired without a page.

## Archives

docs-site builds one archive per example. Each needs an entry under the
`archive-attachments` extension in the docs-site playbooks (the extension
produces `.tar.gz`, published at the site root):

```yaml
- component: 'solutions'
  output_archive: 'chat-room-go.tar.gz'
  file_patterns:
    - '**/examples/_attachments/clients/chat-room/go/**'
```

Repeat for `java`, `nodejs`, `python`, `rust`, for each
`data-transforms/<lang>/<name>`, and for `security/oidc-entra`.

## Doc Detective

`tests/doc-detective/specs/` holds standalone specs (never inline `// (step)`
comments). Each spec has a `-run` test and a separate `-cleanup` test so a
failed run still tears its stack down. Every rpk profile a spec creates is
prefixed `examples-`. Paths inside the specs are relative to the spec file
(`relativePathBase: file`), so the suite runs from any directory:

```bash
npx doc-detective runTests --config docs/modules/examples/tests/doc-detective/.doc-detective.json
```

CI should run this in the `docs` workflow when a PR touches
`docs/modules/examples/**`, on a runner with Docker, `rpk`, Go (`rpk transform
build` fetches TinyGo), and Rust with `rustup target add wasm32-wasip1`, with
`REDPANDA_VERSION` and `REDPANDA_CONSOLE_VERSION` exported from the same
version lookup the solutions use. The specs are not part of
`tools/run-doc-detective.sh`, which is per solution.
