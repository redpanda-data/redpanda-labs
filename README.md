[![Slack](https://img.shields.io/badge/Slack-Redpanda%20Community-blue)](https://redpanda.com/slack)

## Redpanda Labs

<img align="right" width="25%" src="images/redpanda_lab2.png">Redpanda Labs is the home for examples, experiments and research projects created by the Customer Success and Marketing teams at Redpanda.

Labs projects intend to showcase what is possible to achieve with Redpanda as the centerpiece of your streaming data architecture. Some of these projects may make it into the product, and many will not, but what they will do is provide examples, guidance, best practices, and most importantly give you ideas for how you can use Redpanda in your own projects.

Contributions are welcome. Just fork the repo (or submodule) and send a pull request against the upstream `main` branch.

## Lab Projects

| Project       | Description   |
| ------------- | ------------- |
| [`clients`](https://github.com/redpanda-data/redpanda-labs/clients) | A collection of Redpanda clients available in different programming languages. |
| [`data-transforms`](https://github.com/redpanda-data/redpanda-labs/tree/main/data-transforms) | Example topic data transforms powered by WebAssembly (Wasm). |
| [`docker-compose`](https://github.com/redpanda-data/redpanda-labs/tree/main/docker-compose) | Example deployments of Redpanda, Redpanda Console, and Redpanda Connectors using Docker. |
| [`kubernetes`](https://github.com/redpanda-data/redpanda-labs/tree/main/kubernetes) | Examples of deploying and managing Redpanda in Kubernetes. |
| [`redpanda-edge-agent`](https://github.com/redpanda-data/redpanda-edge-agent) | Lightweight Internet of Things (IoT) agent that forwards events from the edge. |

## Update submodules

```
git submodule update --remote --recursive
```
