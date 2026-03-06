"""OIDC token management for Redpanda AI Gateway."""

import os
import time

import httpx
from authlib.integrations.httpx_client import AsyncOAuth2Client


class GatewayAuth:
    """Manages OIDC client_credentials tokens for the Redpanda AI Gateway."""

    DEFAULT_ISSUER = "https://auth.prd.cloud.redpanda.com"
    DEFAULT_AUDIENCE = "cloudv2-production.redpanda.cloud"

    def __init__(
        self,
        client_id: str | None = None,
        client_secret: str | None = None,
        gateway_url: str | None = None,
        gateway_id: str | None = None,
        issuer: str | None = None,
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
        self._issuer = (
            issuer
            or os.environ.get("REDPANDA_ISSUER", self.DEFAULT_ISSUER)
        ).rstrip("/")
        self._audience = (
            audience
            or os.environ.get("REDPANDA_AUDIENCE", self.DEFAULT_AUDIENCE)
        )
        self._client = AsyncOAuth2Client(
            client_id=client_id or os.environ["REDPANDA_CLIENT_ID"],
            client_secret=client_secret or os.environ["REDPANDA_CLIENT_SECRET"],
        )
        self._token: str = ""
        self._expires_at: float = 0.0
        self._token_endpoint: str | None = None

    @property
    def gateway_url(self) -> str:
        """The resolved gateway base URL."""
        return self._gateway_url

    async def _discover_token_endpoint(self) -> str:
        """Fetch the token endpoint from the OIDC discovery document."""
        if self._token_endpoint:
            return self._token_endpoint

        discovery_url = f"{self._issuer}/.well-known/openid-configuration"
        async with httpx.AsyncClient() as http:
            resp = await http.get(discovery_url)
            resp.raise_for_status()
            self._token_endpoint = resp.json()["token_endpoint"]
        return self._token_endpoint

    async def get_token(self) -> str:
        """Return a valid Bearer token, refreshing if expired."""
        if self._token and time.time() < self._expires_at - 30:
            return self._token

        token_endpoint = await self._discover_token_endpoint()
        token_response = await self._client.fetch_token(
            url=token_endpoint,
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
