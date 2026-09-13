# Security

The code in this repository is reference material for learning and evaluation.
It runs Redpanda with authentication and TLS disabled so that a solution starts
in seconds on a laptop. Do not run a solution unchanged in production; each
overview page has a Production considerations table that says what to change.

## Reporting a vulnerability

If you find a security problem in a solution's code, its dependencies, or the
automation in this repository, email security@redpanda.com. Do not open a
public issue. Include the solution slug, the version from its overview page
(`:page-solution-version:`), and steps to reproduce.

For vulnerabilities in Redpanda itself, see the
[Redpanda security policy](https://github.com/redpanda-data/redpanda/security/policy).

## Dependencies

Dependabot watches GitHub Actions, npm, Go modules, Python, Docker images, and
Compose files across every solution (`.github/dependabot.yml`). The nightly
workflow runs every solution against the latest Redpanda, Redpanda Console, and
Redpanda Connect images and opens an issue when one stops working.
