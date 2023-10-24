import logging
import json
import requests
from io import BytesIO
from struct import pack, unpack
from fastavro import parse_schema
from fastavro import schemaless_reader
from fastavro import schemaless_writer


class SchemaRegistry:
    """Interact with the Redpanda Schema Registry.

    Arguments:
    uri -- address of the Schema Registry (e.g. https://localhost:8081)
    """

    def __init__(self, uri):
        self.base_uri = uri
        self.cache = {}

    def register(self, schema):
        """Register schema and return the schema ID.

        Arguments:
        schema -- Avro schema definition (dict)
        """
        subject = f"{schema['name']}-value"
        r = requests.post(
            url=f"{self.base_uri}/subjects/{subject}/versions",
            data=json.dumps({"schema": json.dumps(schema)}),
            headers={"Content-Type": "application/vnd.schemaregistry.v1+json"},
            timeout=10,
        )
        r.raise_for_status()
        schema_id = r.json()["id"]
        logging.info("Registered schema id: %s", schema_id)
        return schema_id

    def fetch(self, schema_id):
        """Returns the schema from the cache,
        or fetches it from the Schema Registry.

        Arguments:
        schema_id -- schema id to fetch from the Schema Registry
        """
        parsed_schema = self.cache.get(schema_id, None)
        if parsed_schema:
            logging.debug("Fetched schema from cache for id: %s", schema_id)
            return parsed_schema
        r = requests.get(url=f"{self.base_uri}/schemas/ids/{schema_id}", timeout=10)
        r.raise_for_status()
        schema = r.json()["schema"]
        parsed_schema = parse_schema(json.loads(schema))
        return parsed_schema

    @staticmethod
    def encode(data, schema, schema_id):
        """Encode data as Avro with Schema Registry framing:

        | Bytes | Desc                     |
        | ----- | ------------------------ |
        | 0     | Magic byte `0`           |
        | 1-4   | 4-byte schema ID (int)   |
        | 5+    | Binary encoded Avro data |

        Arguments:
        data      -- data to encode as Avro
        schema    -- parsed schema used to encode the data
        schema_id -- schema id to encode in the Schema Registry framing
        """
        with ContextBytesIO() as bio:
            # Write the magic byte and schema id to the buffer
            bio.write(pack(">bI", 0, schema_id))
            # Write the Avro encoded data to the buffer
            schemaless_writer(bio, schema, data)
            return bio.getvalue()

    def decode(self, data):
        """Decode Avro data with Schema Registry framing.

        Arguments:
        data -- Avro data to decode
        """
        with ContextBytesIO(data) as payload:
            _, schema_id = unpack(">bI", payload.read(5))
            msg_schema = self.fetch(schema_id)
            msg = schemaless_reader(payload, msg_schema)
            return msg


class ContextBytesIO(BytesIO):
    """Wrapper for BytesIO for use with a context manager."""

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
        return False
