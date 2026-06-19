# Total Free iOS App Instructions

Native SwiftUI app for the **Total Free** community platform. Open to all users with
role-based privileges; talks **directly to Supabase** with RLS as the security boundary.

## Project Facts

- Bundle identifier: `ca.totalfree.admin` (kept for APNs continuity; display name is "Total Free").
- Backend: Supabase project `ettemffrunjqoqwkaxmg` — the same one as the
  `TotalFree-Claude` web app. No custom API server.
- Auth: Supabase GoTrue (email + password) with refresh; session in the Keychain.
- Data: PostgREST + SECURITY DEFINER RPCs. Connection config is in
  `TotalFreeAdmin/Services/SupabaseConfig.swift`.
- Ship ONLY the Supabase **publishable** key. NEVER embed the `service_role` key.
- Roles (mirror the web app): `isStaff` = admin/owner/moderator; `isOwner` = admin/owner.
- Privileges are surfaced by role but ENFORCED by Row Level Security — never trust the client.
- APNs: register device tokens in `device_tokens` (platform `ios`); the `send-push`
  edge function delivers using `APNS_BUNDLE_ID` (must equal the bundle id) as apns-topic.

## Architecture rules

- The app's data layer (`Services/API.swift`) mirrors `TotalFree-Claude/src/lib/api.js`.
  Keep them aligned: when the web data layer changes a table/RPC contract, update here too.
- All Supabase calls go through `SupabaseClient` (in `Services/TotalFreeAPIClient.swift`)
  and the typed `extension` in `API.swift`. Don't scatter raw URLSession code in views.
- Reads/writes flow through `AppState.load { … }` / `AppState.perform { … }` so token
  refresh and error surfacing stay centralized.
- Don't reintroduce schema that no longer exists (e.g. member `status`, invite codes).

## Verify

```bash
xcodebuild -project TotalFreeAdmin.xcodeproj -scheme TotalFreeAdmin \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

After backend/schema changes, re-check that RLS still scopes data correctly (anon sees
only active listings) and smoke-test browse, auth, post, request/message, alerts, and
(as staff) the moderation queue, reports, and people & roles.

## Docs

- `README.md` — setup, source map, configuration, APNs.
- Reference backend: `/Volumes/Forrest/Users/Forrest/Github/TotalFree-Claude`
  (schema in `supabase/migrations`, data layer in `src/lib/api.js`).
