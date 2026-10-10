import unittest

from apple_iap import (
    APPLE_PRODUCTS,
    AppleIapConfig,
    apple_account_token,
    deleted_account_fingerprint,
    duplicate_purchase_action,
    validate_transaction_claims,
)


class AppleIapPolicyTests(unittest.TestCase):
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
        with self.assertRaises(RuntimeError):
            AppleIapConfig.from_environment({})


if __name__ == "__main__":
    unittest.main()
