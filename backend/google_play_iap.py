"""Google Play purchase verification helpers and Developer API access."""

from __future__ import annotations

import hashlib
import hmac
from typing import Any, Mapping
from urllib.parse import quote

import httpx

from purchase_policy import PLAY_PRODUCTS, account_binding


ANDROID_PACKAGE_NAME = "com.agdevelops.ainotescanner"
ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
ANDROID_PUBLISHER_BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3"


class GooglePlayApiError(RuntimeError):
    """A safe-to-report Google API failure without purchase-token details."""

    def __init__(self, message: str, *, invalid_purchase: bool = False):
        super().__init__(message)
        self.invalid_purchase = invalid_purchase


def validate_play_purchase(
    purchase: Mapping[str, Any], *, product_id: str, uid: str
) -> dict[str, Any]:
    """Validate Google-owned purchase fields and derive server-owned grants."""
    pack = PLAY_PRODUCTS.get(product_id)
    if pack is None:
        raise ValueError("Unsupported Google Play product.")
    response_product = purchase.get("productId")
    if response_product is not None and response_product != product_id:
        raise ValueError("Google Play returned a different product.")
    try:
        purchase_state = int(purchase.get("purchaseState", -1))
    except (TypeError, ValueError) as exc:
        raise ValueError("Google Play purchase state is invalid.") from exc
    if purchase_state != 0:
        raise ValueError("Google Play purchase is not completed.")
    if purchase.get("purchaseType") == 2:
        raise ValueError("Rewarded Play products are not store purchases.")
    try:
        quantity = int(purchase.get("quantity") or 1)
    except (TypeError, ValueError) as exc:
        raise ValueError("Google Play purchase quantity is invalid.") from exc
    if quantity != 1:
        raise ValueError("Only one credit pack may be granted per purchase.")

    expected_account = account_binding(uid)
    external_account = purchase.get("obfuscatedExternalAccountId")
    account_bound = bool(external_account)
    if account_bound and not hmac.compare_digest(str(external_account), expected_account):
        raise PermissionError("Google Play purchase belongs to another account.")

    return {
        "product_id": product_id,
        "credits": int(pack["credits"]),
        "plan": str(pack["plan"]),
        "uid_hash": expected_account,
        "account_bound": account_bound,
        "purchase_time_millis": str(purchase.get("purchaseTimeMillis") or ""),
    }


def play_purchase_key(purchase_token: str) -> str:
    """Hash a Play token before using it as a Firestore ledger key."""
    return hashlib.sha256(purchase_token.encode("utf-8")).hexdigest()


def duplicate_play_purchase_action(
    existing: Mapping[str, Any] | None, uid: str
) -> str:
    """Make retries idempotent and reject a token claimed by another UID."""
    if existing is None:
        return "grant"
    if existing.get("uidHash") == account_binding(uid):
        return "already_processed"
    raise PermissionError("Google Play purchase belongs to another account.")


def _google_access_token() -> str:
    """Use the Cloud Run runtime identity; no service-account key is needed."""
    try:
        import google.auth
        from google.auth.transport.requests import Request

        credentials, _ = google.auth.default(scopes=[ANDROID_PUBLISHER_SCOPE])
        credentials.refresh(Request())
        if not credentials.token:
            raise RuntimeError("Google authentication returned no access token.")
        return credentials.token
    except Exception as exc:
        raise GooglePlayApiError("Google Play verification is unavailable.") from exc


def _play_api_request(
    method: str,
    package_name: str,
    product_id: str,
    purchase_token: str,
    *,
    timeout: float = 18,
) -> dict[str, Any]:
    package = quote(package_name, safe="")
    product = quote(product_id, safe="")
    token = quote(purchase_token, safe="")
    url = (
        f"{ANDROID_PUBLISHER_BASE}/applications/{package}/purchases/products/"
        f"{product}/tokens/{token}"
    )
    try:
        response = httpx.request(
            method,
            url,
            headers={"Authorization": f"Bearer {_google_access_token()}"},
            json={} if method == "POST" else None,
            timeout=timeout,
        )
    except GooglePlayApiError:
        raise
    except httpx.HTTPError as exc:
        raise GooglePlayApiError("Google Play could not confirm the purchase.") from exc

    if response.status_code in (400, 404):
        raise GooglePlayApiError(
            "Google Play purchase could not be verified.", invalid_purchase=True
        )
    if response.status_code in (401, 403):
        raise GooglePlayApiError("Google Play verification is not authorized.")
    if response.status_code == 429 or response.status_code >= 500:
        raise GooglePlayApiError("Google Play verification is temporarily unavailable.")
    if not response.is_success:
        raise GooglePlayApiError("Google Play verification failed.")
    if not response.content:
        return {}
    try:
        payload = response.json()
    except ValueError as exc:
        raise GooglePlayApiError("Google Play returned an invalid response.") from exc
    if not isinstance(payload, dict):
        raise GooglePlayApiError("Google Play returned an invalid response.")
    return payload


def get_play_purchase(
    package_name: str, product_id: str, purchase_token: str
) -> dict[str, Any]:
    return _play_api_request("GET", package_name, product_id, purchase_token)


def consume_play_purchase(
    package_name: str, product_id: str, purchase_token: str
) -> None:
    _play_api_request("POST", package_name, product_id, purchase_token)
