# Changelog

## Unreleased — 2026-06-18 — Mobile social sign-in

### Added

- Google, Apple, Microsoft, and Facebook sign-in buttons on the native auth sheet.
- Social sign-in rows now use provider logo assets instead of generic system icons.
- App bundle metadata now uses the user-facing name `Total Free` instead of the
  internal target name in iOS permission prompts.
- Mobile OAuth now starts at `https://totalfree.ca/auth/mobile-start`, so iOS
  permission prompts show the Total Free domain instead of `supabase.co`.
- Supabase OAuth callback handling through the `https://totalfree.ca/auth/mobile-callback`
  bridge to `ca.totalfree.admin://auth/callback`, storing the returned session in
  the existing Keychain session flow.

## Unreleased — 2026-06-16 — Message grouping and Resend verification

### Changed

- Messages now open as item groups first, then requester/request rows, then the conversation thread.
- Sign-up verification uses the shared Supabase Auth email flow with the TotalFree Resend hook and a `totalfree.ca` confirmation redirect.

## Unreleased — 2026-06-16 — Source-linked listing actions

### Changed

- Unclaimed organization and business listings now show a primary "View original source" button instead of opening the in-app request flow.

## Unreleased — 2026-06-16 — App logo refresh

### Changed

- Replaced the app icon and in-app logo asset with the new TotalFree artwork.

## Unreleased — 2026-06-16 — APNs registration metadata

### Fixed

- Push registration now sends the app bundle id plus the APNs environment
  (`sandbox` for Debug/development, `production` for Release), so the
  TotalFree-Claude `send-push` function can route each device token to the
  correct Apple push gateway.

## Unreleased — 2026-06-15 (d) — Owner self-service, multi-photo, toast, copy

### Added

- **Owner self-service** on your own listing (⋯ menu in the detail): Edit (content
  edits re-enter the review queue), Withdraw a pending post, Mark completed,
  Edit & resubmit a rejected post, and Delete. Gated by `listing.edit.own` /
  `listing.delete.own` and enforced by RLS.
- **Multiple photos:** Post now accepts up to 5 photos; listing detail shows a
  swipeable gallery. Added an additive `image_urls[]` column (migration in
  TotalFree-Claude); `image_url` stays as the cover for web compatibility.

### Changed

- Renamed the **Home** category label to **Household** (key unchanged, so data and
  the web app stay compatible).
- Replaced the blocking "Heads up" confirmation alert with a non-blocking **toast**
  that auto-dismisses — so approving/rejecting in moderation returns you straight to
  the queue with a brief confirmation instead of an interrupting dialog.

## Unreleased — 2026-06-15 (c) — Photos, map pin, openable alerts, badges, clickable rows

### Added

- **Photo upload** on Post (give-away and wanted): pick a photo, auto-downscaled to
  JPEG and uploaded to Supabase Storage (`listing-media`, public bucket), set as the
  listing image.
- **Map pin location picker** (MapKit) in the Post "Where" section — pan to drop a
  pin, reverse-geocoded to fill area/city, captures lat/lng. Works on iPhone + iPad,
  no location permission needed.
- **Openable alerts:** tapping a notification opens a detail that marks it read and
  deep-links to the related listing or conversation (`ListingLoaderView` /
  `RequestLoaderView`).
- **Staff badges:** unread counts of pending listings + open reports badge the
  Admin/Manage tab and the Moderation queue / Reports rows; refresh on load,
  foreground, and after actions.
- **User directory rows open** a `UserDetailView` (profile, joined date, their posts,
  and role management when permitted).
- Detail screens for scanner finds, org claims, and businesses, with quick
  swipe-to-approve/reject on the lists.

### Changed

- Reports rows now open the reported listing; resolve moved to swipe actions.
- Every staff list row is now tappable (opens a detail) in addition to inline/swipe
  actions.

## Unreleased — 2026-06-15 (b) — Staff hub, posting in My Stuff, permission gating

### Added

- **Role-adaptive staff hub** (replaces the simple Admin tab). Titled **Manage**
  for moderators and **Admin** for owners. Each section appears only if the person
  holds the matching permission and covers: moderation queue, scanner finds
  (approve/reject candidates), safety reports, organization claims, business
  approvals, conversations (read any, read-only), analytics, and the user directory
  (role changes gated by `role.manage`).
- **Edit any listing** from the moderation detail (gated by `listing.edit.any`).
- **`my_perms()`** SQL function (migration in TotalFree-Claude) returning the
  caller's effective permission keys by reusing `has_perm` per permission. The app
  loads these into `AppState.perms` so staff UI is gated by real privileges, fully
  consistent with RLS — and respects custom roles, not just the built-in ones.
- New screens: CandidatesView, ClaimsView, SponsorsView, ConversationsView,
  AnalyticsView, EditListingView.

### Changed

- **Posting moved into My Stuff:** the standalone Post tab is gone; a **+ New post**
  button on My Stuff (visible in both My listings and Requests) opens the post form
  as a sheet. Frees a tab slot for the staff hub.
- Notifications refresh when the app returns to the foreground (in addition to
  on-appear, pull-to-refresh, and after actions); the Alerts tab shows a live unread
  badge.

### Fixed

- AuthUser metadata decode (`try?` already flattens the optional — removed an
  invalid optional-chain that broke the build).

## Unreleased — 2026-06-15 (a) — Rebuilt for TotalFree-Claude (Supabase) + opened to all users

Major rework: the app moved off the old Cloudflare Worker admin API and now talks
**directly to the TotalFree-Claude Supabase backend** (project `ettemffrunjqoqwkaxmg`),
and changed from a staff-only admin tool into an app **open to all users with
role-based privileges**.

### Added

- Direct Supabase integration: GoTrue auth (email + password, token refresh),
  PostgREST data access, and SECURITY DEFINER RPCs — all gated by Row Level Security.
- `SupabaseClient` transport (`Services/TotalFreeAPIClient.swift`) + typed data layer
  (`Services/API.swift`) mirroring the web app's `src/lib/api.js`.
- `SupabaseConfig.swift` with the project URL + publishable key and shared vocabulary
  (categories, conditions, source labels).
- Member experience: Browse + search, Listing detail with request + report, Post
  (offer / wanted), My Stuff (my listings, requests, and per-request message threads),
  Alerts (in-app notifications), Account/profile.
- Role-gated Admin tab: moderation queue (approve/reject via `moderate_listing`),
  safety reports (resolve), and Owner-only People & roles (`admin_list_users` /
  `set_user_role`).
- Sign in / Join flow for everyone, with email-verification awareness.
- APNs device-token registration into the Supabase `device_tokens` table.

### Changed

- Authentication now uses Supabase sessions (access + refresh tokens) in the Keychain
  instead of the Worker login endpoint.
- App display name is now "Total Free" (bundle id unchanged: `ca.totalfree.admin`).
- Privilege model follows the web app: staff = moderator/owner/admin; owner = admin/owner.

### Removed

- The Cloudflare Worker API client and all `/api/...` endpoints.
- Features that no longer exist in the new schema: invite codes and member account
  `status` management.

## Earlier (Worker-era, superseded)

- Added APNs registration for the staff iOS app after moderator/admin sign-in.
- Added Push Notifications entitlement wiring for `ca.totalfree.admin`.
- Added Worker device-token registration support and APNs setup documentation.
