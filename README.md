# PetPal

PetPal is a Flutter web app for organizing pet care, health records, and household tasks.

## Features

- Create and manage pet profiles.
- Track feeding, walking, grooming, medication, and other care tasks.
- Assign tasks to household members.
- Record health information and care history.
- Sign in and save account data with Supabase.
- Deploy the web app to Vercel.

## Run locally

Install Flutter, then run:

```bash
flutter pub get
flutter run -d chrome
```

To create a production web build:

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL="your-supabase-url" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="your-supabase-publishable-key"
```

The generated web files are placed in `build/web`.

## Supabase configuration

The app reads these values at build time:

- `SUPABASE_URL` — your Supabase project URL.
- `SUPABASE_PUBLISHABLE_KEY` — your Supabase publishable/anonymous key.

Never use or expose the Supabase `service_role` key in the Flutter app.

PetPal stores account data in the `petpal_accounts` table. Row Level Security should allow each authenticated user to access only their own row.

## Deploy to Vercel

Deployments are handled by GitHub Actions. Push to `main` after adding these repository secrets in GitHub:

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
VERCEL_TOKEN
VERCEL_ORG_ID
VERCEL_PROJECT_ID
```

The workflow builds Flutter for the web and deploys `build/web` to Vercel:

```text
.github/workflows/deploy-flutter-vercel.yml
```

## Project structure

- `lib/main.dart` — app screens, navigation, forms, and authentication UI.
- `lib/store.dart` — pet data, task scheduling, local persistence, and Supabase account syncing.
- `supabase/schema.sql` — database table and Row Level Security setup.
- `.github/workflows/deploy-flutter-vercel.yml` — automated Flutter web deployment.

## Useful checks

```bash
flutter analyze
flutter test
flutter build web --release
```
