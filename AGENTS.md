# Total Free iOS App Instructions

Native SwiftUI staff-only admin app for Total Free Community.

## Project Facts

- Bundle identifier: `ca.totalfree.admin`.
- Backend boundary: call the Cloudflare Worker API only.
- Do not put Supabase, Cloudflare, R2, or APNs provider secrets in the app.
- Authentication uses the Worker login endpoint and stores the session in Keychain.
- Push notifications register the APNs device token with the Worker after an active staff user signs in.
- Debug builds use APNs sandbox; Release builds use APNs production.

## Verify

Run from this folder:

```bash
xcodebuild -project TotalFreeAdmin.xcodeproj -scheme TotalFreeAdmin -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Docs

- Read `README.md` for setup commands.
- Read `docs/ARCHITECTURE.md` before changing API boundaries or role behavior.
