# Redaction Transform Demo

This demo shows how Redpanda Data Transforms can perform redaction of JSON messages.

# Overview

The redaction transform source is available in [GitHub](https://github.com/pmw-rp/redaction-transform).

The demo runs using docker compose, with the following containers:

* Redpanda Broker (1x)
* Redpanda Console
* Owlshop
* Data Transform Deploy

# Demo

### Configuration

The redaction flow can be customised by editing the local redaction configuration file ([config.yaml](config.yaml)), which is part of this demo repository.

### Clone the Repo

This demo includes the redaction transform as a Git submodule, therefore when cloning the demo be sure to include `--recurse-submodules`:

```shell
git clone --recurse-submodules https://github.com/pmw-rp/redaction-demo.git
```

### Build & Run

```shell
docker compose build
docker compose up --detach
```

### Validate

* Navigate to http://localhost:8080 to see the Redpanda Console
* Choose Topics -> owlshop-orders-redacted and see the redacted orders

### Stop the Demo

```shell
docker compose down
```