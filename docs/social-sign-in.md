# Native Apple and Google sign-in

The server validates signed provider ID tokens and a single-use five-minute nonce before issuing Berynda access/refresh tokens. Berynda stores its session in Keychain. Google access is discarded after identity exchange; no Drive, contacts, or Gmail scopes are requested.

Existing email addresses are never automatically merged. Sign in using the existing method first, then connect Apple or Google in Profile. Provider subjects are unique, and linking challenges are bound to the authenticated Berynda account.

## Apple

- Bundle identifier: `org.berynda.ios`, Team: `KHMPLP3CXQ`.
- Enable Sign in with Apple for the primary App ID and regenerate the App Store provisioning profile.
- App entitlement: `com.apple.developer.applesignin = [Default]`.
- Backend environment: `SOCIAL_AUTH_APPLE_CLIENT_ID=org.berynda.ios`.
- Update the existing `APP_STORE_PROFILE_BASE64` GitHub Actions secret with the new App Store profile before archiving.

## Google

Create OAuth clients in the Berynda Google Cloud project:

1. iOS client: bundle `org.berynda.ios`, Team `KHMPLP3CXQ`, App Store ID `6808289031`.
2. Web application client: Berynda API. The native ID-token exchange does not use a server redirect URL or client secret.
3. Add the iOS client ID in reverse dot order to `CFBundleURLTypes` in both `project.yml` and `Berynda/Info.plist` (for example `123.apps.googleusercontent.com` becomes `com.googleusercontent.apps.123`).
4. Set backend `SOCIAL_AUTH_GOOGLE_IOS_CLIENT_ID` to the iOS client ID and `SOCIAL_AUTH_GOOGLE_CLIENT_ID` to the Web client ID.
5. Complete Google's audience/consent configuration and test with an authorized account before enabling production access.

The app obtains public client IDs from `/api/v1/auth/social/config/` and initializes GoogleSignIn with both IDs. It hides Google sign-in unless its installed callback scheme matches. Disabled providers are also rejected by the server. No private Google client secret is embedded in the app.

## Validation

Server regression tests cover signature, issuer, audience, expiry, nonce, Google authorized presenter, replay rejection, blocked users, explicit linking, account collisions and the native JSON endpoints. iOS tests cover the transport contract and error handling. A device test with real provider credentials remains required before release.
