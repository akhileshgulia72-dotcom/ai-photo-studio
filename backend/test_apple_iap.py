import base64
from datetime import datetime, timedelta, timezone
import unittest

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID

from apple_iap import (
    APPLE_PRODUCTS,
    AppleIapConfig,
    apple_account_token,
    deleted_account_fingerprint,
    duplicate_purchase_action,
    validate_transaction_claims,
)


class AppleIapPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root_key = ec.generate_private_key(ec.SECP256R1())
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Test Root CA")])
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        cls.root_certificate = (
            x509.CertificateBuilder()
            .subject_name(name)
            .issuer_name(name)
            .public_key(cls.root_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(days=1))
            .not_valid_after(now + timedelta(days=30))
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .sign(cls.root_key, hashes.SHA256())
            .public_bytes(serialization.Encoding.DER)
        )
        cls.private_key = ec.generate_private_key(ec.SECP256R1()).private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )

    def valid_environment(self, **overrides):
        environment = {
            "APPLE_APP_ID": "1234567890",
            "APPLE_IAP_KEY_ID": "TESTKEY123",
            "APPLE_IAP_ISSUER_ID": "00000000-0000-0000-0000-000000000000",
            "APPLE_IAP_PRIVATE_KEY": self.private_key.decode("ascii"),
            "APPLE_ROOT_CERTIFICATES_B64": base64.b64encode(
                self.root_certificate
            ).decode("ascii"),
        }
        environment.update(overrides)
        return environment

    def transaction(self, **overrides):
        values = {
            "productId": "com.agdevelops.vyro.credits250",
            "bundleId": "com.agdevelops.ainotescanner",
            "type": "Consumable",
            "transactionId": "100000000000001",
            "purchaseDate": 1_700_000_000_000,
            "revocationDate": None,
            "quantity": 1,
            "appAccountToken": apple_account_token("uid-1"),
            "environment": "Sandbox",
        }
        values.update(overrides)
        return values

    def test_apple_products_grant_server_defined_amounts(self):
        self.assertEqual(APPLE_PRODUCTS["com.agdevelops.vyro.credits250"]["credits"], 250)
        self.assertEqual(APPLE_PRODUCTS["com.agdevelops.vyro.credits800"]["credits"], 800)

    def test_account_token_is_stable_uuid_and_user_specific(self):
        self.assertEqual(apple_account_token("uid-1"), apple_account_token("uid-1"))
        self.assertNotEqual(apple_account_token("uid-1"), apple_account_token("uid-2"))
        self.assertEqual(len(apple_account_token("uid-1")), 36)

    def test_valid_transaction_claims_select_server_owned_credit_amount(self):
        grant = validate_transaction_claims(self.transaction(), uid="uid-1")
        self.assertEqual(grant["credits"], 250)
        self.assertEqual(grant["product_id"], "com.agdevelops.vyro.credits250")

    def test_pro_product_grants_800_credits(self):
        grant = validate_transaction_claims(
            self.transaction(productId="com.agdevelops.vyro.credits800"),
            uid="uid-1",
        )
        self.assertEqual(grant["credits"], 800)

    def test_rejects_wrong_account_product_bundle_type_or_revoked_purchase(self):
        invalid = (
            {"appAccountToken": apple_account_token("uid-2")},
            {"productId": "client-supplied-product"},
            {"bundleId": "com.other.app"},
            {"type": "Non-Consumable"},
            {"revocationDate": 1_700_000_000_001},
            {"quantity": 2},
            {"quantity": 0},
            {"purchaseDate": None},
            {"purchaseDate": 0},
            {"purchaseDate": "not-a-timestamp"},
        )
        for change in invalid:
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_transaction_claims(self.transaction(**change), uid="uid-1")

    def test_idempotency_does_not_regrant_and_rejects_cross_account_replay(self):
        self.assertEqual(duplicate_purchase_action(None, "uid-1"), "grant")
        self.assertEqual(
            duplicate_purchase_action({"uid": "uid-1"}, "uid-1"),
            "already_processed",
        )
        with self.assertRaises(ValueError):
            duplicate_purchase_action({"uid": "uid-1"}, "uid-2")

    def test_deleted_account_purchase_ledger_remains_private_and_idempotent(self):
        fingerprint = deleted_account_fingerprint("uid-1")
        self.assertNotIn("uid-1", fingerprint)
        self.assertEqual(
            duplicate_purchase_action({"uidHash": fingerprint}, "uid-1"),
            "already_processed",
        )
        with self.assertRaises(ValueError):
            duplicate_purchase_action({"uidHash": fingerprint}, "uid-2")

    def test_missing_server_credentials_fail_closed(self):
        required_variables = (
            "APPLE_APP_ID",
            "APPLE_IAP_KEY_ID",
            "APPLE_IAP_ISSUER_ID",
            "APPLE_IAP_PRIVATE_KEY",
            "APPLE_ROOT_CERTIFICATES_B64",
        )
        for variable in required_variables:
            with self.subTest(variable=variable), self.assertRaisesRegex(
                RuntimeError, variable
            ):
                AppleIapConfig.from_environment(
                    self.valid_environment(**{variable: ""})
                )

    def test_requires_positive_ascii_numeric_apple_app_id(self):
        for invalid_app_id in ("0", "-1", "1.2", "abc", "١٢٣"):
            with self.subTest(app_id=invalid_app_id), self.assertRaisesRegex(
                RuntimeError, "APPLE_APP_ID"
            ):
                AppleIapConfig.from_environment(
                    self.valid_environment(APPLE_APP_ID=invalid_app_id)
                )

    def test_parses_app_id_separately_from_bundle_id(self):
        config = AppleIapConfig.from_environment(self.valid_environment())
        self.assertEqual(config.app_apple_id, 1234567890)
        self.assertEqual(config.bundle_id, "com.agdevelops.ainotescanner")

    def test_rejects_malformed_base64_root_certificate(self):
        with self.assertRaisesRegex(RuntimeError, "APPLE_ROOT_CERTIFICATES_B64"):
            AppleIapConfig.from_environment(
                self.valid_environment(APPLE_ROOT_CERTIFICATES_B64="not/base64!")
            )

    def test_rejects_missing_or_non_der_root_certificate(self):
        with self.assertRaisesRegex(RuntimeError, "APPLE_ROOT_CERTIFICATES_B64"):
            AppleIapConfig.from_environment(
                self.valid_environment(APPLE_ROOT_CERTIFICATES_B64="")
            )
        with self.assertRaisesRegex(RuntimeError, "DER X.509"):
            AppleIapConfig.from_environment(
                self.valid_environment(
                    APPLE_ROOT_CERTIFICATES_B64=base64.b64encode(b"not a certificate").decode()
                )
            )

    def test_normalizes_escaped_newlines_in_secret_manager_pem_key(self):
        escaped_key = self.private_key.decode("ascii").replace("\n", "\\n")
        config = AppleIapConfig.from_environment(
            self.valid_environment(APPLE_IAP_PRIVATE_KEY=escaped_key)
        )
        self.assertEqual(config.private_key, self.private_key.strip())

    def test_rejects_invalid_private_key_without_disclosing_it(self):
        with self.assertRaisesRegex(RuntimeError, "APPLE_IAP_PRIVATE_KEY") as raised:
            AppleIapConfig.from_environment(
                self.valid_environment(APPLE_IAP_PRIVATE_KEY="not a private key")
            )
        self.assertNotIn("not a private key", str(raised.exception))

    def test_sandbox_allowlist_is_explicit_and_never_wildcarded(self):
        config = AppleIapConfig.from_environment(
            self.valid_environment(APPLE_IAP_SANDBOX_UID_ALLOWLIST=" uid-1,uid-2 ")
        )
        self.assertEqual(config.sandbox_uid_allowlist, frozenset({"uid-1", "uid-2"}))
        with self.assertRaisesRegex(RuntimeError, "cannot contain a wildcard"):
            AppleIapConfig.from_environment(
                self.valid_environment(APPLE_IAP_SANDBOX_UID_ALLOWLIST="*")
            )


if __name__ == "__main__":
    unittest.main()
