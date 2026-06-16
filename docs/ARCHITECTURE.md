# Architecture Notes

## Agreed Direction (current)

The iOS app is a native client over the **TotalFree-Claude Supabase backend**, talking
directly to Supabase. It mirrors how the web app works.

```text
iOS App ─┬─ Supabase Auth (GoTrue)      sign in / sign up / refresh
         ├─ Supabase PostgREST          tables (listings, requests, messages, …)
         └─ Supabase RPC (SECURITY DEFINER)  moderate_listing, admin_list_users,
                                             set_user_role, report_listing
                         │
                  Row Level Security  ← the real security boundary
```

There is **no Cloudflare Worker API** anymore. The app ships only the Supabase
**publishable** key (safe in a client bundle); the `service_role` key is never embedded.
Authorization is enforced by Postgres RLS / `has_perm(...)`, not by the client.

> Superseded: the previous design routed everything through a Cloudflare Worker
> (`iOS Admin App -> Worker -> Supabase / R2`) and kept the app staff-only. That is
> no longer how this app works.

## Audience & privileges

The app is open to everyone. UI is shown by role; the server enforces it.

- **Signed out:** browse + search the public feed, view listings.
- **Member (`user`, also `partner` / `sponsor`):** post, request, message, alerts, profile.
- **Staff (`moderator` / `owner` / `admin`):** + Admin tab (moderation queue, reports).
- **Owner (`owner` / `admin`):** + People & roles (`set_user_role`).

Mirrors the web app: `isStaff = {admin, owner, moderator}`, `isOwner = {admin, owner}`.

## Screens

- **Browse** — public feed with search + category/source/kind filters.
- **Listing detail** — full listing, request flow, report flow.
- **Post** — create a free item or "wanted" (→ `pending_review`).
- **My Stuff** — my listings, my requests (incoming/outgoing), per-request chat.
- **Alerts** — in-app notifications (bell badge = unread).
- **Account** — profile, verification state, sign out.
- **Admin** (staff) — moderation queue, safety reports, and (owners) people & roles.

## Data surface used

PostgREST tables: `listings`, `requests`, `messages`, `reports`, `notifications`,
`profiles`, `device_tokens`.

RPCs: `moderate_listing(p_id, p_status)`, `report_listing(p_listing, p_reason, p_note)`,
`admin_list_users()`, `set_user_role(target, new_role)`.

Auth: `/auth/v1/token` (password + refresh grants), `/auth/v1/signup`.

Keep this surface in sync with the web data layer at
`TotalFree-Claude/src/lib/api.js`.

## Notifications

In-app notifications come from the `notifications` table. iOS push is delivered by the
`send-push` Supabase edge function, which reads `device_tokens` (platform `ios`). The
app registers its APNs token there after sign-in. The function's `APNS_BUNDLE_ID` must
equal the app bundle id (`ca.totalfree.admin`).
