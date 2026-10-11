"""Apple consumable purchase verification and idempotency policy."""

from __future__ import annotations

import base64
import binascii
import hashlib
import uuid
from dataclasses import dataclass
from typing import Any, Mapping

from cryptography import x509
from cryptography.exceptions import UnsupportedAlgorithm
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


APPLE_BUNDLE_ID = "com.agdevelops.ainotescanner"
APPLE_PRODUCTS = {
    "com.agdevelops.vyro.credits250": {"credits": 250, "name": "creator"},
    "com.agdevelops.vyro.credits800": {"credits": 800, "name": "pro_credits"},
}


def apple_account_token(uid: str) -> str:
    """Return a stable RFC 4122 UUID for StoreKit's appAccountToken field."""
    digest = bytearray(hashlib.sha256(f"vyro-app-account:{uid}".encode()).digest()[:16])
    digest[6] = (digest[6] & 0x0F) | 0x50
    digest[8] = (digest[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(digest)))


def deleted_account_fingerprint(uid: str) -> str:
    """Pseudonymous account key retained only for IAP replay prevention."""
    return hashlib.sha256(f"vyro-deleted-account:{uid}".encode()).hexdigest()


def validate_transaction_claims(
    transaction: Mapping[str, Any], *, uid: str, bundle_id: str = APPLE_BUNDLE_ID
) -> dict[str, Any]:
    """Validate signed Apple claims and return server-owned grant metadata."""
    product_id = transaction.get("productId")
    pack = APPLE_PRODUCTS.get(product_id)
    if pack is None:
        raise ValueError("Unsupported Apple product.")
    if transaction.get("bundleId") != bundle_id:
        raise ValueError("Apple transaction belongs to a different app.")
    if transaction.get("type") != "Consumable":
        raise ValueError("Apple transaction is not a consumable product.")
    if not transaction.get("transactionId"):
        raise ValueError("Apple transaction ID is missing.")
    try:
        purchase_date = int(transaction.get("purchaseDate"))
    except (TypeError, ValueError) as exc:
        raise ValueError("Apple transaction purchase date is invalid.") from exc
    if purchase_date <= 0:
        raise ValueError("Apple transaction is not a completed purchase.")
    if transaction.get("revocationDate") is not None:
        raise ValueError("Apple transaction was revoked.")
    quantity_value = transaction.get("quantity")
    try:
        quantity = int(1 if quantity_value is None else quantity_value)
    except (TypeError, ValueError) as exc:
        raise ValueError("Apple transaction quantity is invalid.") from exc
    if quantity != 1:
        raise ValueError("Only one credit pack may be purchased per transaction.")
    token = transaction.get("appAccountToken")
    if not token or str(token).lower() != apple_account_token(uid).lower():
        raise ValueError("Apple transaction is not associated with this account.")
    return {
        "transaction_id": str(transaction["transactionId"]),
        "product_id": product_id,
        "credits": int(pack["credits"]),
        "environment": str(transaction.get("environment") or ""),
    }


def duplicate_purchase_action(existing: Mapping[str, Any] | None, uid: str) -> str:
    """Choose the idempotent action for a transaction already in Firestore."""
    if existing is None:
        return "grant"
    if existing.get("uid") == uid or existing.get("uidHash") == deleted_account_fingerprint(uid):
        return "already_processed"
    raise ValueError("Apple transaction was already used by another account.")


@dataclass(frozen=True)
class AppleIapConfig:
    bundle_id: str
    app_apple_id: int
    key_id: str
    issuer_id: str
    private_key: bytes
    root_certificates: tuple[bytes, ...]
    sandbox_uid_allowlist: frozenset[str]

    @classmethod
    def from_environment(cls, environ: Mapping[str, str]) -> "AppleIapConfig":
        required = (
            "APPLE_APP_ID",
            "APPLE_IAP_KEY_ID",
            "APPLE_IAP_ISSUER_ID",
            "APPLE_IAP_PRIVATE_KEY",
            "APPLE_ROOT_CERTIFICATES_B64",
        )
        missing = [name for name in required if not environ.get(name, "").strip()]
        if missing:
            raise RuntimeError("Apple IAP configuration is incomplete: " + ", ".join(missing))

        app_id_value = environ["APPLE_APP_ID"].strip()
        if not app_id_value.isascii() or not app_id_value.isdecimal():
            raise RuntimeError("APPLE_APP_ID must be a positive numeric App Store ID.")
        app_apple_id = int(app_id_value)
        if app_apple_id <= 0:
            raise RuntimeError("APPLE_APP_ID must be a positive numeric App Store ID.")

        roots: list[bytes] = []
        encoded_roots = environ["APPLE_ROOT_CERTIFICATES_B64"].split(",")
        for encoded in encoded_roots:
            value = encoded.strip()
            if not value:
                raise RuntimeError(
                    "APPLE_ROOT_CERTIFICATES_B64 contains an empty certificate entry."
                )
            try:
                certificate_bytes = base64.b64decode(value, validate=True)
                certificate = x509.load_der_x509_certificate(certificate_bytes)
                constraints = certificate.extensions.get_extension_for_class(
                    x509.BasicConstraints
                ).value
            except (binascii.Error, ValueError, x509.ExtensionNotFound) as exc:
                raise RuntimeError(
                    "APPLE_ROOT_CERTIFICATES_B64 must contain Base64-encoded "
                    "DER X.509 CA certificates."
                ) from exc
            if not constraints.ca:
                raise RuntimeError(
                    "APPLE_ROOT_CERTIFICATES_B64 may contain only CA certificates."
                )
            roots.append(certificate_bytes)
        if not roots:
            raise RuntimeError("No Apple root certificates are configured.")

        key = environ["APPLE_IAP_PRIVATE_KEY"].replace("\\n", "\n").strip().encode("utf-8")
        try:
            parsed_key = serialization.load_pem_private_key(key, password=None)
        except (TypeError, ValueError, UnsupportedAlgorithm) as exc:
            raise RuntimeError(
                "APPLE_IAP_PRIVATE_KEY must be a valid PEM-encoded App Store Connect .p8 key."
            ) from exc
        if (
            not isinstance(parsed_key, ec.EllipticCurvePrivateKey)
            or parsed_key.curve.name != "secp256r1"
        ):
            raise RuntimeError(
                "APPLE_IAP_PRIVATE_KEY must be an App Store Connect P-256 .p8 key."
            )

        sandbox_uids = frozenset(
            uid.strip()
            for uid in environ.get("APPLE_IAP_SANDBOX_UID_ALLOWLIST", "").split(",")
            if uid.strip()
        )
        if "*" in sandbox_uids:
            raise RuntimeError("APPLE_IAP_SANDBOX_UID_ALLOWLIST cannot contain a wildcard.")

        return cls(
            bundle_id=environ.get("APPLE_IAP_BUNDLE_ID", "").strip() or APPLE_BUNDLE_ID,
            app_apple_id=app_apple_id,
            key_id=environ["APPLE_IAP_KEY_ID"].strip(),
            issuer_id=environ["APPLE_IAP_ISSUER_ID"].strip(),
            private_key=key,
            root_certificates=tuple(roots),
            sandbox_uid_allowlist=sandbox_uids,
        )


def verify_apple_transaction(
    signed_transaction: str,
    config: AppleIapConfig,
) -> tuple[dict[str, Any], str]:
    """Verify the client JWS, then fetch and verify Apple's latest transaction."""
    from appstoreserverlibrary.api_client import AppStoreServerAPIClient
    from appstoreserverlibrary.models.Environment import Environment
    from appstoreserverlibrary.signed_data_verifier import (
        SignedDataVerifier,
        VerificationException,
    )

    environments = (Environment.PRODUCTION, Environment.SANDBOX)
    last_error: Exception | None = None
    for environment in environments:
        if environment == Environment.SANDBOX:
            verifier = SignedDataVerifier(
                list(config.root_certificates), True, environment, config.bundle_id
            )
        else:
            verifier = SignedDataVerifier(
                list(config.root_certificates),
                True,
                environment,
                config.bundle_id,
                config.app_apple_id,
            )
        try:
            submitted = verifier.verify_and_decode_signed_transaction(signed_transaction)
            transaction_id = submitted.transactionId
            if not transaction_id:
                raise ValueError("Apple transaction ID is missing.")

            client = AppStoreServerAPIClient(
                config.private_key,
                config.key_id,
                config.issuer_id,
                config.bundle_id,
                environment,
            )
            latest_response = client.get_transaction_info(transaction_id)
            latest_jws = latest_response.signedTransactionInfo
            if not latest_jws:
                raise ValueError("Apple did not return current transaction information.")
            latest = verifier.verify_and_decode_signed_transaction(latest_jws)
            claims = {
                "productId": latest.productId,
                "bundleId": latest.bundleId,
                "type": latest.rawType,
                "transactionId": latest.transactionId,
                "purchaseDate": latest.purchaseDate,
                "revocationDate": latest.revocationDate,
                "quantity": latest.quantity,
                "appAccountToken": latest.appAccountToken,
                "environment": latest.rawEnvironment,
            }
            if claims["transactionId"] != transaction_id:
                raise ValueError("Apple transaction identifiers do not match.")
            return claims, environment.value
        except (VerificationException, ValueError) as error:
            last_error = error
            continue
        except Exception as error:
            # API/network failures must not fall back into a credit grant.
            raise RuntimeError("Apple transaction status could not be confirmed.") from error

    raise ValueError("Apple transaction could not be verified.") from last_error
