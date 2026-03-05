"""OIDC token management for Redpanda AI Gateway."""

import os
import time

from authlib.integrations.httpx_client import AsyncOAuth2Client


class GatewayAuth:
    """Manages OIDC client_credentials tokens for the Redpanda AI Gateway."""

    DEFAULT_TOKEN_ENDPOINT = "https://auth.prd.cloud.redpanda.com/oauth/token"

    def __init__(
        self,
        client_id: str | None = None,
        client_secret: str | None = None,
        gateway_url: str | None = None,
        gateway_id: str | None = None,
        token_endpoint: str | None = None,
        audience: str | None = None,
    ) -> None:
        self._gateway_url = (
            gateway_url
            or os.environ.get(
                "REDPANDA_GATEWAY_URL",
                "https://ai-gateway.d6b2mdhdvf8ruqkbl2mg.clusters.rdpa.co",
            )
        )
        self._gateway_id = (
            gateway_id or os.environ.get("REDPANDA_GATEWAY_ID", "d6b3mk93mouc73cortj0")
        )
        self._token_endpoint = (
            token_endpoint
            or os.environ.get("REDPANDA_TOKEN_ENDPOINT", self.DEFAULT_TOKEN_ENDPOINT)
        )
        self._audience = (
            audience
            or os.environ.get("REDPANDA_AUDIENCE", "cloudv2-production.redpanda.cloud")
        )
        self._client = AsyncOAuth2Client(
            client_id=client_id or os.environ["REDPANDA_CLIENT_ID"],
            client_secret=client_secret or os.environ["REDPANDA_CLIENT_SECRET"],
        )
        self._token: str = ""
        self._expires_at: float = 0.0

    @property
    def gateway_url(self) -> str:
        """The resolved gateway base URL."""
        return self._gateway_url

    async def get_token(self) -> str:
        """Return a valid Bearer token, refreshing if expired."""
        if self._token and time.time() < self._expires_at - 30:
            return self._token

        token_response = await self._client.fetch_token(
            url=self._token_endpoint,
            grant_type="client_credentials",
            audience=self._audience,
        )
        self._token = token_response["access_token"]
        self._expires_at = time.time() + token_response.get("expires_in", 3600)
        return self._token

    async def get_headers(self) -> dict[str, str]:
        """Return auth + gateway ID headers for requests."""
        token = await self.get_token()
        return {
            "Authorization": f"Bearer {token}",
            "rp-aigw-id": self._gateway_id,
        }

    async def close(self) -> None:
        """Close the underlying HTTP client."""
        await self._client.aclose()
