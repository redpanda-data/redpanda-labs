import os

# tag::config[]
# Connection settings come from environment variables:
#   REDPANDA_BROKERS         comma-separated bootstrap servers (default localhost:19092)
#   REDPANDA_SASL_USERNAME   SASL/SCRAM user; when set, TLS and SASL are enabled
#   REDPANDA_SASL_PASSWORD   SASL/SCRAM password
#   REDPANDA_SASL_MECHANISM  SCRAM-SHA-256 (default) or SCRAM-SHA-512
TOPIC = os.environ.get("REDPANDA_TOPIC", "chat-room")


def client_config():
    """Return the keyword arguments shared by the admin, producer, and consumer."""
    config = {
        "bootstrap_servers": os.environ.get("REDPANDA_BROKERS", "localhost:19092").split(","),
    }
    username = os.environ.get("REDPANDA_SASL_USERNAME")
    if username:
        config.update(
            security_protocol="SASL_SSL",
            sasl_mechanism=os.environ.get("REDPANDA_SASL_MECHANISM", "SCRAM-SHA-256").upper(),
            sasl_plain_username=username,
            sasl_plain_password=os.environ.get("REDPANDA_SASL_PASSWORD", ""),
        )
    return config
# end::config[]
