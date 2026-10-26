# Supabase setup

`schema.sql` creates the shared online data model for PetPal. It includes households, members, invitations, pets, care tasks, task completions, health records, and household updates.

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

Flutter already uses Supabase for email authentication, Google SSO, and sign-out. The app still keeps its current pet/task state in local preferences while the remote repository is being added. Do not treat local mode as multi-device synchronization yet.

## Next implementation step

The Flutter store now loads and saves the signed-in user's household data through Supabase. The database policies in `schema.sql` remain the security boundary; Flutter should not be the only place that checks roles.

The household invitation flow creates a secure seven-day invitation code for the invited email. The admin can copy the code from the app and send it to the invitee. The invitee signs in with that email, opens the profile menu, chooses **Accept invitation**, and pastes the code. Automatic email delivery still requires a Supabase Edge Function and an email provider such as Resend or SendGrid.
