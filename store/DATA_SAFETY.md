# Play Console → App content → Data safety (v1.1.0)
- Does your app collect or share user data? **Yes** (via Google Play Games SDK, only when the player signs in).
- Data types: **App activity → Other actions / In-app game progress** (cloud save, achievements, leaderboard score); **Personal info → User IDs** (Play Games player ID). Purpose: App functionality. Collected, not shared. Optional (user can choose not to sign in).
- Financial info: **not collected by the app** — purchases are handled by Google Play (Billing); the app only receives purchase tokens.
- Encrypted in transit: **Yes** (Google SDKs use HTTPS).
- Users can request deletion: **Yes** — via Play Games settings (delete game data) / uninstall.
- No ads, no analytics SDKs. Ads declaration: **No ads**.
- In-app purchases: **Yes** (declare on the store listing / content rating questionnaire).
