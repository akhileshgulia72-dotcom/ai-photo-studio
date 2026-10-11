import unittest

from google_play_iap import (
    duplicate_play_purchase_action,
    play_purchase_key,
    validate_play_purchase,
)
from purchase_policy import account_binding


class GooglePlayIapTests(unittest.TestCase):
    def purchase(self, **overrides):
        values = {
            "productId": "vyro_creator_150",
            "purchaseState": 0,
            "consumptionState": 0,
            "purchaseTimeMillis": "1700000000000",
            "quantity": 1,
            "obfuscatedExternalAccountId": account_binding("uid-1"),
        }
        values.update(overrides)
        return values

    def test_valid_purchase_uses_server_owned_credits_and_plan(self):
        grant = validate_play_purchase(
            self.purchase(), product_id="vyro_creator_150", uid="uid-1"
        )
        self.assertEqual(grant["credits"], 150)
        self.assertEqual(grant["plan"], "creator")
        self.assertEqual(grant["uid_hash"], account_binding("uid-1"))
        self.assertTrue(grant["account_bound"])

    def test_pro_purchase_grants_server_owned_pro_values(self):
        grant = validate_play_purchase(
            self.purchase(productId="vyro_pro_500"),
            product_id="vyro_pro_500",
            uid="uid-1",
        )
        self.assertEqual(grant["credits"], 500)
        self.assertEqual(grant["plan"], "pro")

    def test_rejects_unlisted_product_wrong_product_pending_and_quantity(self):
        invalid = (
            (self.purchase(), "unknown", "uid-1"),
            (self.purchase(productId="vyro_pro_500"), "vyro_creator_150", "uid-1"),
            (self.purchase(purchaseState=2), "vyro_creator_150", "uid-1"),
            (self.purchase(purchaseType=2), "vyro_creator_150", "uid-1"),
            (self.purchase(quantity=2), "vyro_creator_150", "uid-1"),
        )
        for data, product_id, uid in invalid:
            with self.subTest(data=data, product_id=product_id):
                with self.assertRaises(ValueError):
                    validate_play_purchase(data, product_id=product_id, uid=uid)

    def test_rejects_a_purchase_bound_to_a_different_account(self):
        with self.assertRaises(PermissionError):
            validate_play_purchase(
                self.purchase(obfuscatedExternalAccountId=account_binding("uid-2")),
                product_id="vyro_creator_150",
                uid="uid-1",
            )

    def test_legacy_unbound_purchase_can_be_claimed_once(self):
        grant = validate_play_purchase(
            self.purchase(obfuscatedExternalAccountId=None),
            product_id="vyro_creator_150",
            uid="uid-1",
        )
        self.assertFalse(grant["account_bound"])

    def test_duplicate_token_is_idempotent_and_owner_checked(self):
        self.assertEqual(duplicate_play_purchase_action(None, "uid-1"), "grant")
        entry = {"uidHash": account_binding("uid-1")}
        self.assertEqual(
            duplicate_play_purchase_action(entry, "uid-1"), "already_processed"
        )
        with self.assertRaises(PermissionError):
            duplicate_play_purchase_action(entry, "uid-2")

    def test_purchase_token_is_hashed_before_ledger_storage(self):
        token = "private-google-purchase-token"
        key = play_purchase_key(token)
        self.assertEqual(len(key), 64)
        self.assertNotIn(token, key)


if __name__ == "__main__":
    unittest.main()
