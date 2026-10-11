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
5. Grant the Cloud Run runtime service account the required Play Console permissions and enable the Android Publisher API.
6. Verify the Android package name exactly matches Play Console.
7. Run one Google Play license-test purchase for each product.
8. Confirm Firestore `play_purchases` prevents a second credit grant for the same token and rejects cross-account replay.
9. Confirm a duplicated AdMob SSV `transaction_id` cannot grant twice.
10. Confirm a fabricated client reward request cannot grant credits.
11. Confirm a successful image generation returns `generationId`, `storagePath`, and `outputImageUrl`.
12. Confirm free download uses `/v1/my-creations/{id}/watermarked`.
13. Confirm paid users can download the original image.
14. Test an OpenAI timeout and verify the 10 credits are refunded once.
15. Test a malformed image and verify credits are refunded once.
16. Test app restart during an IAP purchase; purchaseStream must redeliver and backend must remain idempotent. Verify Play consumption happens only after the Firestore grant commits.
17. Test account switching; a purchase token must never be credited to a different Firebase UID.
18. Keep `ENABLE_TEST_OUTPUT=false` in production.
19. Configure Apple IAP in Cloud Run without replacing other service settings:
    set `APPLE_APP_ID`, `APPLE_IAP_BUNDLE_ID`, `APPLE_IAP_KEY_ID`,
    `APPLE_IAP_ISSUER_ID`, and `APPLE_ROOT_CERTIFICATES_B64` as ordinary
    environment variables; inject `APPLE_IAP_PRIVATE_KEY` from Secret Manager.
    Keep `APPLE_IAP_SANDBOX_UID_ALLOWLIST` empty in production and use a
    Secret Manager-backed exact UID list only during controlled TestFlight
    testing. Follow the official Apple PKI certificate conversion steps in
    `ENVIRONMENT.md`; never disable verification or use unofficial roots.
20. In App Store Connect, confirm the numeric Apple App ID, In-App Purchase
    Key ID, Issuer ID, and bundle ID match the values configured for Cloud Run.
    Keep the `.p8` private key out of Git, Flutter, and logs.
21. Create both Apple products as consumables with the exact IDs documented in
    `ENVIRONMENT.md`, complete the Paid Apps Agreement/tax/banking setup, and
    test each SKU with a sandbox tester whose Firebase UID is explicitly
    allowlisted. Confirm only the configured credits are granted once and that
    an unlisted UID, duplicate transaction, or cross-account replay is rejected.
22. After TestFlight testing, remove the sandbox UID allowlist and confirm
    production transactions remain verifiable.
23. Enable Sign in with Apple for the iOS App ID and Firebase Authentication;
    verify sign-in and guest-account linking on an iPhone.
24. Test `DELETE /v1/account` with a disposable account. Confirm its Firebase
    Auth record, profile, generations, and Storage files are removed while
    Apple transaction replay protection remains pseudonymous.
25. Before each image generation, verify the AI processing disclosure is shown
    and the user must affirmatively continue.
