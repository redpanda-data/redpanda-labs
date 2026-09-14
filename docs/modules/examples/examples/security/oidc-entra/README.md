# Unified identity with Azure Entra ID (OIDC)

Docker Compose stack for the docs page
`streaming:manage:security/oidc-azure-entra.adoc`: three Redpanda brokers,
Redpanda Console with OIDC and basic login, and a Redpanda Connect generator.
`client.js` is a KafkaJS producer that authenticates to Redpanda with
SASL/OAUTHBEARER using an Entra ID client-credentials token.

```bash
cp .env.example .env            # fill in the Entra ID values
docker compose up --detach --wait
rpk profile create oidc-entra --from-profile profile.yaml
npm install && node client.js get-sub-value
node client.js
docker compose down -v
```
