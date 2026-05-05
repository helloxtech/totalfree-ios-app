# Architecture Notes

## Agreed Direction

The mobile admin app is a thin native client over the existing Total Free backend:

```text
iOS Admin App -> Cloudflare Worker API -> Supabase / R2
```

The app never connects directly to Supabase or R2. This keeps secrets out of the mobile bundle and keeps moderation logic centralized.

## Roles

The Worker remains the source of truth for role checks:

- `moderator`: review posts and reports
- `admin`: moderator permissions plus member status and invite-code operations
- `super_admin`: admin permissions plus role management

The iOS app hides unavailable tabs, but the Worker must still reject unauthorized requests.

## Current iOS Screens

- Login: email/password staff sign-in
- Queue: dashboard stats and pending post review
- Post Review Detail: post content, privacy checklist, approve/reject actions
- Reports: open safety reports, sorted by severity
- Report Detail: report context and resolve/dismiss actions
- Members: member search, status, role controls
- Access: invite-code creation and code list

## API Surface Used

The app currently uses these Worker endpoints:

- `POST /api/auth/login`
- `GET /api/me`
- `GET /api/admin/dashboard`
- `POST /api/admin/posts/{id}/approve`
- `POST /api/admin/posts/{id}/reject`
- `POST /api/admin/reports/{id}/resolve`
- `GET /api/admin/users`
- `PATCH /api/admin/users/{id}/status`
- `PATCH /api/admin/users/{id}/role`
- `POST /api/admin/invite-codes`
- `POST /api/push/devices`
- `DELETE /api/push/devices/{deviceToken}`

## Push Notifications

The app never stores APNs provider secrets. It registers with iOS for remote notifications, then sends the APNs device token to the Worker after staff authorization is confirmed. The Worker stores active device tokens in Supabase and uses the Apple APNs provider key to deliver moderation alerts.

Build behavior:

- Debug: APNs sandbox token registration
- Release: APNs production token registration

## Android-Ready Rule

Future Android should not copy Swift code or business decisions. It should copy the contract:

- Same HTTPS endpoints
- Same request/response JSON shapes
- Same token behavior
- Same role permissions
- Same moderation state machine

Recommended next step before Android: publish a small `docs/api/openapi.yaml` from the Worker routes and keep it versioned with backend changes.

## Known Phase 2 Gaps

- Add a refresh-token endpoint or session renewal flow for long-lived mobile sessions.
- Add an authenticated admin photo endpoint for pending-post photos, because public photo URLs should not expose pending content.
- Add device-based QA on real iPhones before TestFlight.
