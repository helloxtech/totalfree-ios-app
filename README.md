# Total Free Admin iOS App

Native iPhone admin app for Total Free Community student moderators.

## Purpose

This app gives approved staff users a fast mobile workflow for:

- Reviewing pending posts
- Approving or rejecting posts
- Reviewing safety reports
- Resolving reports
- Managing members, roles, and account status
- Creating and reviewing invite codes

The app is intentionally staff-only. Regular community members should continue using the public website.

## Architecture

- UI: SwiftUI, iOS 17+
- Authentication: existing Total Free Worker login endpoint
- Session storage: iOS Keychain
- Backend boundary: Cloudflare Worker API
- Database/storage: accessed only by the Worker, not by the app

The app must not contain Supabase, R2, or Cloudflare secrets. It only calls the public HTTPS API and uses the signed-in user's access token.

## Push Notifications

The admin app requests notification permission only after an active staff user signs in. It sends the APNs device token to the Cloudflare Worker, and the Worker sends APNs notifications when moderation notifications are created.

APNs setup requirements:

- Apple Developer Push Notifications capability enabled for `ca.totalfree.admin`
- `APNS_TOPIC=ca.totalfree.admin` in the Worker environment
- Worker secrets set with `wrangler secret put APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_PRIVATE_KEY`
- Supabase schema applied so `public.push_device_tokens` exists

Debug builds register against APNs sandbox. Release builds register against APNs production.

## Open In Xcode

Open:

```bash
open TotalFreeAdmin.xcodeproj
```

Use the shared scheme:

```text
TotalFreeAdmin
```

Current bundle identifier:

```text
ca.totalfree.admin
```

## Verify Build

From this folder:

```bash
xcodebuild -project TotalFreeAdmin.xcodeproj -scheme TotalFreeAdmin -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Future Android

Android should be a native Kotlin/Jetpack Compose app that uses the same Cloudflare Worker API contract. Do not duplicate business rules in Android. Keep all authorization, moderation rules, and data access inside the Worker.

Before building Android, create a versioned API contract from the Worker routes, preferably OpenAPI, then generate typed clients for iOS and Android.
