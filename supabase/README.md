# Supabase setup

`schema.sql` creates the private online data model for PetPal. Each signed-in account owns its household data, including pets, care tasks, task completions, and health records. Household invitations and cross-account sharing are not part of the app flow.

## Apply the schema

1. Create or open the PetPal project in Supabase.
2. Open **SQL Editor**.
3. Paste in `supabase/schema.sql` and run it.
4. Enable the authentication providers you want under **Authentication → Providers**.
5. Keep the project URL and publishable key available for Flutter:

```sh
flutter run \
  --dart-define=SUPABASE_URL="https://your-project.supabase.co" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="your-publishable-key"
```

## What is connected today

Flutter uses Supabase for email authentication, Google SSO, sign-out, and saving the signed-in account's household data. Without the `--dart-define` values, the app remains fully local and uses browser/device storage.

The database policies in `schema.sql` remain the security boundary. Existing invitation SQL objects may remain in an already-created Supabase project, but the current Flutter app no longer calls them.
