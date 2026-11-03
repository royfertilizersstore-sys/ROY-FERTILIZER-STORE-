# ROY FERTILIZER STORE — Version 2

## Included
- First-launch Admin account setup (no built-in/default credentials)
- Admin + Staff sign-in with bcrypt password hashes stored in local SQLite
- Admin can create Staff accounts, disable/re-enable Staff accounts, and change their own password
- Staff permissions: record sales, view sales, view dashboard and add customer records
- Admin permissions: all Staff functions plus stock/product management, purchases, supplier records, reports, and staff management
- Logout and current-password verification for password changes
- Offline-first local SQLite database
- Assamese / English toggle for primary navigation and labels
- Product and stock management
- Purchase entries increase stock
- Sales entries reduce stock and block negative inventory
- Customer and supplier records
- PDF invoice preview/print for sales
- Basic sales and purchase reports
- No DBT or iFMS screens or integration

## Offline + Online status
The app works offline and stores records locally in SQLite. It is **online-sync ready in architecture only**; actual cloud sync is not enabled. To synchronize between devices, a backend such as Firebase or Supabase must be created and configured with authentication, database rules, backups, and conflict-safe synchronization. No credentials were provided, so no cloud service is connected.

## Build APK
1. Install Flutter SDK and Android Studio.
2. In this folder run: `flutter create --platforms=android .` (if platform files are not present).
3. Run `flutter pub get`.
4. Run `flutter run` to test.
5. Run `flutter build apk --release`.
6. APK path: `build/app/outputs/flutter-apk/app-release.apk`.

## Important production gaps
This is a functional starter project, not yet a complete commercial accounting system. It does not yet include edit/delete, invoice history storage, multi-line invoices, expense tracking, GST tax calculation, cloud sync, backup/restore, or full Assamese translation of every form. Login is local to this device; it is not a substitute for a server-backed identity system and does not prevent someone with direct access to the device/database from bypassing the app. Use device screen lock, restrict device access, and keep secure backups. Validate prices, units, invoice/tax rules, and all records before business use.

## Login setup and use
1. On first launch, create the Admin username and password. Use a unique password of at least 10 characters.
2. Sign in with the Admin account.
3. Tap the staff/accounts icon in the top bar to create Staff accounts. Give each staff member a unique username and a temporary password of at least 10 characters.
4. Staff should sign in and change their password using the key icon.
5. Admin can disable a Staff account from Staff accounts. Disabled accounts cannot sign in.
6. Use Logout when leaving the app.

Passwords are stored as bcrypt hashes, not plaintext. Authentication and roles are enforced by the app's local UI/data flow; this starter has not undergone a security audit. Do not treat this as high-assurance access control for a shared or rooted device.
