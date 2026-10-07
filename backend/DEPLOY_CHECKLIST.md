# VYRO release checklist

## Credit economy
- New user: 5 credits
- Rewarded ad: 5 credits
- Generation: 10 credits

## Before deployment
1. Deploy the backend.
2. Set all environment variables in ENVIRONMENT.md.
3. Set the AdMob SSV callback URL.
4. Set the rewarded ad unit reward amount to 5.
5. Grant the Google Play service account the required Play Console permissions.
6. Verify the Android package name exactly matches Play Console.
7. Run one Google Play license-test purchase for each product.
8. Confirm Firestore `iap_purchases` prevents a second credit grant for the same token.
9. Confirm a duplicated AdMob SSV `transaction_id` cannot grant twice.
10. Confirm a fabricated client reward request cannot grant credits.
11. Confirm a successful image generation returns `generationId`, `storagePath`, and `outputImageUrl`.
12. Confirm free download uses `/v1/my-creations/{id}/watermarked`.
13. Confirm paid users can download the original image.
14. Test an OpenAI timeout and verify the 10 credits are refunded once.
15. Test a malformed image and verify credits are refunded once.
16. Test app restart during an IAP purchase; purchaseStream must redeliver and backend must remain idempotent.
17. Test account switching; a purchase token must never be credited to a different Firebase UID.
18. Keep `ENABLE_TEST_OUTPUT=false` in production.
