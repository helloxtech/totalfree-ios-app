# Total Free iOS App

Native iPhone app for the **Total Free** community platform — a warm place to find
and share genuinely free items, local business freebies, and free learning
resources across Metro Vancouver.

The app is **open to everyone** with role-based privileges:

- **Anyone (signed out):** browse and search the public feed, open listings.
- **Members (signed in + verified email):** post free items / "wanted" posts,
  request items, private per-request messaging, in-app alerts, manage their profile.
- **Staff (moderator / owner / admin):** everything above, plus a role-adaptive
  hub — **Manage** for moderators, **Admin** for owners — covering the moderation
  queue, scanner finds, safety reports, organization claims, business approvals,
  conversations (read-only), analytics, and the user directory.

Privileges are shown based on the person's **real permissions** (the `my_perms()`
function) and **enforced by Supabase Row Level Security** — the client never decides
who can do what. This respects custom security roles, not just the built-in ones.

Members post from **My Stuff** (the **+ New post** button), not a separate tab.

## Architecture

- **UI:** SwiftUI, iOS 17+, tab-based (Browse · Post · My Stuff · Alerts · Admin · Account).
- **Backend:** talks **directly to Supabase** — the same project (`ettemffrunjqoqwkaxmg`)
  that powers the [TotalFree-Claude](../TotalFree-Claude) web app. No custom server
  in between.
  - **Auth:** Supabase GoTrue (`/auth/v1/...`) — email + password, social OAuth,
    with token refresh.
  - **Data:** PostgREST (`/rest/v1/...`) for tables and SECURITY DEFINER RPCs
    (`moderate_listing`, `admin_list_users`, `set_user_role`, `report_listing`).
  - **Security boundary:** Row Level Security. The app ships only the **publishable**
    key (safe in a client bundle); it never contains the `service_role` key.
- **Session:** access + refresh tokens stored in the iOS Keychain.
- **Mirrors** the web app's data layer (`TotalFree-Claude/src/lib/api.js`) so both
  clients speak to the database the same way.
- **Auth emails:** sign-up still goes through Supabase Auth. Confirmation emails
  are sent by the shared `TotalFree-Claude/supabase/functions/send-email` Auth hook
  via Resend; the iOS signup sets the confirmation redirect to `https://totalfree.ca/`.
- **Social sign-in:** Google, Apple, Microsoft, and Facebook start from
  `https://totalfree.ca/auth/mobile-start` so iOS permission prompts show
  `totalfree.ca`, then return through `https://totalfree.ca/auth/mobile-callback`,
  which opens the app at `ca.totalfree.admin://auth/callback`.

### Source map

```
TotalFreeAdmin/
  App/            TotalFreeAdminApp (entry) · AppState (session, role, data)
  Models/         AdminModels.swift — all Codable models + roles + insert/RPC bodies
  Services/       SupabaseConfig (URL + publishable key + vocab)
                  TotalFreeAPIClient (SupabaseClient: Auth + PostgREST + RPC transport)
                  API.swift (typed data functions over SupabaseClient)
                  KeychainSessionStore · PushNotificationService
  Views/          RootView (+ StaffHubView) · AccessView (AuthView)
                  BrowseView · ListingDetailView · PostView · MyStuffView
                  NotificationsView · AccountView
                  Staff: QueueViews (ModerationView + edit) · ReportsView ·
                         MembersView (UsersView) · CandidatesView · ClaimsView ·
                         SponsorsView · ConversationsView · AnalyticsView · EditListingView
                  Components (shared UI)
```

Staff sections are gated in the UI by `AppState.perms` (loaded from `my_perms()`)
and by RLS on the server. The `my_perms()` migration lives in the TotalFree-Claude
repo (`supabase/migrations/20260615170000_my_perms.sql`).

## Configuration

Connection details live in `TotalFreeAdmin/Services/SupabaseConfig.swift`:

```swift
static let url = URL(string: "https://ettemffrunjqoqwkaxmg.supabase.co")!
static let publishableKey = "sb_publishable_…"   // safe to ship; RLS protects data
```

To point the app at a different Supabase project, change those two values. Nothing
else is environment-specific.

For social sign-in, the app starts OAuth through the Total Free web domain:

```text
https://totalfree.ca/auth/mobile-start
```

Supabase returns to the web callback bridge:

```text
https://totalfree.ca/auth/mobile-callback
```

The bridge then opens the registered iOS callback scheme:

```text
ca.totalfree.admin://auth/callback
```

## Push Notifications (APNs)

In-app alerts (the bell tab) work today. For real push:

- The app registers its APNs device token in the Supabase `device_tokens` table
  (`{ user_id, device_token, platform: "ios", apns_environment, bundle_id }`)
  after sign-in.
- The deployed `send-push` edge function reads that table and delivers via APNs.
- The function's `APNS_BUNDLE_ID` secret **must equal the app bundle id**
  (`ca.totalfree.admin`), because it's used as the `apns-topic`.
- Debug builds register against the APNs sandbox; Release builds use production
  (`aps-environment` is driven by the `APNS_ENVIRONMENT` build setting).

Full provider setup lives in `TotalFree-Claude/docs/notification-strategy.md`.

> Note: the bundle id is still `ca.totalfree.admin` to keep the existing APNs /
> provisioning continuity. The user-facing app name is **Total Free**. Renaming the
> bundle id later requires updating `APNS_BUNDLE_ID` to match.

## Open in Xcode

```bash
open TotalFreeAdmin.xcodeproj
```

Shared scheme: `TotalFreeAdmin`. Bundle id: `ca.totalfree.admin`.

## Verify build

```bash
xcodebuild -project TotalFreeAdmin.xcodeproj -scheme TotalFreeAdmin \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Promote a user to staff

Roles can't be self-assigned (a DB trigger blocks it). From the Supabase SQL editor:

```sql
update public.profiles set role = 'admin' where id = '<auth-user-id>';
```

Owners can also change roles in-app from **Admin → People & roles**.

## Future Android

Android should be a native Kotlin/Jetpack Compose app talking to the same Supabase
project, mirroring this app's data layer. Keep all authorization in Supabase RLS;
never duplicate trust rules on the client.
