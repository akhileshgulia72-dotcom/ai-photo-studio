import unittest

from purchase_policy import PLAY_PRODUCTS, account_binding, generation_quality, updated_plan


class PurchasePolicyTests(unittest.TestCase):
    def test_product_packs_match_store_ids_and_credit_grants(self):
        self.assertEqual(PLAY_PRODUCTS["vyro_creator_150"], {"credits": 150, "plan": "creator"})
        self.assertEqual(PLAY_PRODUCTS["vyro_pro_500"], {"credits": 500, "plan": "pro"})

    def test_account_binding_is_stable_and_user_specific(self):
        self.assertEqual(account_binding("user-a"), account_binding("user-a"))
        self.assertNotEqual(account_binding("user-a"), account_binding("user-b"))
        self.assertEqual(len(account_binding("user-a")), 64)

    def test_plan_upgrades_do_not_downgrade_pro(self):
        self.assertEqual(updated_plan("free", "creator"), "creator")
        self.assertEqual(updated_plan("creator", "pro"), "pro")
        self.assertEqual(updated_plan("pro", "creator"), "pro")
        self.assertEqual(updated_plan("premium", "creator"), "premium")

    def test_quality_comes_from_server_plan(self):
        self.assertEqual(generation_quality("free"), "medium")
        self.assertEqual(generation_quality("creator"), "medium")
        self.assertEqual(generation_quality("pro"), "high")
        self.assertEqual(generation_quality("premium"), "high")


if __name__ == "__main__":
    unittest.main()
