# PetPal

Flutter / Dart prototype for the CMPE 137 concept by **Jhenaro Flores and Ryan Darghous**.

## Run

On this Mac, double-click `run_petpal.command` in Finder, then open http://localhost:8080 after Flutter finishes starting. Keep the Terminal window open. The launcher uses the compatible SDK prepared alongside this project when available.

With your own compatible Flutter SDK installed:

```sh
flutter pub get
flutter run -d web-server --web-port 8080
```

Open http://localhost:8080 for the web version. The source was checked using Flutter 3.29.3 / Dart 3.7.2.

For Android or iOS, start an emulator or connect a phone and run `flutter run`. iOS builds need macOS, Xcode, and signing. Native platform builds have not been verified unless listed below.

## What works

- Add, edit, and delete pets, including birthdays, weight, and care notes.
- Create feeding, walking, grooming, medication, and custom care tasks.
- Assign tasks to household profiles; schedule one-time or daily care.
- Browse dates, filter by pet, mark tasks complete, and undo mistakes.
- Prevent duplicate completion on the same date; retain caregiver and timestamp.
- Keep vet visits, vaccinations, medications, allergies, and other health notes.
- Switch local caregiver profiles and see completion history.
- Save data locally across launches and copy a JSON backup.
- In-app reminders when a task becomes due while the app remains open.
- Responsive navigation for mobile and larger screens; optional sample data.

## Prototype boundaries

This is a **private-account prototype**. Without Supabase configuration, household profiles and app data are stored locally on one device. With Supabase configured, users can create accounts and sync their own pets, care tasks, task history, and health records. Cross-account household invitations are not supported.

Reminders are foreground alerts, **not background push or scheduled operating-system notifications**. Background notification delivery needs a platform notification service and permission handling. JSON copy is an export; import is not implemented. Health records are text entries, not file attachments. Browser storage can be cleared, and local preferences are not intended as the sole copy of important health records.

Future ideas in the presentation, including veterinarian discovery and personalized suggestions, are outside this first version.

## Project structure

- `lib/main.dart`: app theme, adaptive navigation, screens, and editing dialogs.
- `lib/store.dart`: local persistence, recurring schedule logic, and completion history.
- `test/store_test.dart`: recurrence, duplicate completion, attribution, and deletion tests.
- `test/widget_test.dart`: first-run and mobile layout workflows.

## Check

```sh
flutter analyze
flutter test
flutter build web
```

Flutter dependencies: [shared_preferences](https://pub.dev/packages/shared_preferences). Compatible SDK downloads: [Flutter archive](https://docs.flutter.dev/install/archive).

## Validation on this Mac

- `flutter analyze --no-pub`: passed, no issues.
- `flutter build web --no-pub`: passed.
- Automated tests are included but could not execute here: the native Flutter test engine crashed during startup; the Chrome runner could not launch a browser. These are **not recorded as passing tests**.
- Android/iOS compilation, device notifications, and cross-device collaboration have not been validated or implemented in this prototype.
