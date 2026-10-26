import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'store.dart';

const ink = Color(0xFF153D3A);
const teal = Color(0xFF147D70);
const cream = Color(0xFFF4F7F5);
const categories = ['Feeding', 'Walking', 'Grooming', 'Medication', 'Other'];
const categoryIcons = [
  Icons.restaurant_rounded,
  Icons.directions_walk_rounded,
  Icons.brush_rounded,
  Icons.medication_rounded,
  Icons.pets_rounded,
];
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var authEnabled =
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
  String? startupError;
  if (authEnabled) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );
    } catch (_) {
      authEnabled = false;
      startupError =
          'Supabase could not be initialized. Check the URL and publishable key.';
    }
  }
  final store = PetPalStore(
    supabaseClient: authEnabled ? Supabase.instance.client : null,
  );
  runApp(
    PetPalApp(
      store: store,
      authEnabled: authEnabled,
      startupError: startupError,
    ),
  );
  // Render the login screen immediately. A slow or unavailable Supabase
  // request must not leave the native simulator on a blank white screen.
  unawaited(store.load());
}
Widget petPhoto(String? photo, {double radius = 30}) {
  Widget fallback() => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFFE6EFDC),
    child: Icon(Icons.pets, size: radius),
  );

  if (photo == null || photo.isEmpty) return fallback();

  try {
    return ClipOval(
      child: Image.memory(
        base64Decode(photo),
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      ),
    );
  } catch (_) {
    return fallback();
  }
}

class PetPalApp extends StatelessWidget {
  final PetPalStore store;
  final bool authEnabled;
  final String? startupError;
  const PetPalApp({
    super.key,
    required this.store,
    this.authEnabled = false,
    this.startupError,
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PetPal',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: cream,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w800, color: ink),
        headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: ink),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cream,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        foregroundColor: ink,
        elevation: 0,
      ),
    ),
    home: AuthGate(
      store: store,
      authEnabled: authEnabled,
      startupError: startupError,
    ),
  );
}

class AuthGate extends StatefulWidget {
  final PetPalStore store;
  final bool authEnabled;
  final String? startupError;
  const AuthGate({
    super.key,
    required this.store,
    required this.authEnabled,
    this.startupError,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? localUser;

  @override
  Widget build(BuildContext context) {
    if (!widget.authEnabled) {
      if (localUser != null) {
        return Home(
          store: widget.store,
          currentUserLabel: localUser,
          onSignOut: () => setState(() => localUser = null),
        );
      }
      return AuthScreen(
        store: widget.store,
        localMode: true,
        startupError: widget.startupError,
        onLocalSignedIn: (name) => setState(() => localUser = name),
      );
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session == null) return AuthScreen(store: widget.store);
        final user = session.user;
        final label =
            (user.userMetadata?['full_name'] as String?)?.trim().isNotEmpty ==
                    true
                ? user.userMetadata!['full_name'] as String
                : user.email ?? 'Signed-in user';
        return Home(
          store: widget.store,
          currentUserLabel: label,
          onSignOut: () => Supabase.instance.client.auth.signOut(),
        );
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  final PetPalStore store;
  final bool localMode;
  final String? startupError;
  final ValueChanged<String>? onLocalSignedIn;
  const AuthScreen({
    super.key,
    required this.store,
    this.localMode = false,
    this.startupError,
    this.onLocalSignedIn,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool creatingAccount = false;
  bool busy = false;
  String? error;
  String? notice;
  bool needsConfirmation = false;

  @override
  void dispose() {
    email.dispose();
    username.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final normalizedEmail = email.text.trim();
    final emailLooksValid = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(normalizedEmail);
    if (!emailLooksValid) {
      setState(() {
        error = 'Enter a valid email address, such as name@example.com.';
        notice = null;
        needsConfirmation = false;
      });
      return;
    }
    if (creatingAccount && username.text.trim().isEmpty) {
      setState(() {
        error = 'Enter a username so your household can recognize you.';
        notice = null;
        needsConfirmation = false;
      });
      return;
    }
    if (password.text.length < 6) {
      setState(() {
        error = 'Your password must be at least 6 characters long.';
        notice = null;
        needsConfirmation = false;
      });
      return;
    }
    if (creatingAccount && password.text != confirmPassword.text) {
      setState(() {
        error = 'The passwords do not match.';
        notice = null;
        needsConfirmation = false;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
      needsConfirmation = false;
    });
    try {
      if (widget.localMode) {
        widget.onLocalSignedIn?.call(
          creatingAccount && username.text.trim().isNotEmpty
              ? username.text.trim()
              : _usernameFromEmail(normalizedEmail),
        );
        return;
      }
      final auth = Supabase.instance.client.auth;
      if (creatingAccount) {
        final response = await auth.signUp(
          email: normalizedEmail,
          password: password.text,
          data: {'full_name': username.text.trim()},
        );
        if (response.session == null && mounted) {
          setState(() {
            notice =
                'Account created. Check your inbox and spam folder, then click the confirmation link before signing in.';
            needsConfirmation = true;
          });
        }
      } else {
        await auth.signInWithPassword(
          email: normalizedEmail,
          password: password.text,
        );
      }
    } on AuthException catch (exception) {
      if (mounted) {
        final friendly = friendlyAuthError(exception, creatingAccount);
        setState(() {
          error = friendly.message;
          needsConfirmation = friendly.needsConfirmation;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error =
                  'We could not reach PetPal. Check your internet connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _usernameFromEmail(String value) =>
      value.split('@').first.trim().isEmpty ? 'PetPal user' : value.split('@').first;

  Future<void> continueWithSso() async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.origin,
      );
    } on AuthException catch (exception) {
      if (mounted) setState(() => error = friendlyAuthError(exception).message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'SSO could not be started. Try email sign in instead.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendConfirmation() async {
    final normalizedEmail = email.text.trim();
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: normalizedEmail,
      );
      if (mounted) {
        setState(
          () =>
              notice =
                  'A new confirmation email was sent. Check your inbox and spam folder.',
        );
      }
    } on AuthException catch (exception) {
      if (mounted) setState(() => error = friendlyAuthError(exception).message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error =
                  'The confirmation email could not be resent. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.pets_rounded, color: teal, size: 52),
                  const SizedBox(height: 12),
                  Text(
                    creatingAccount
                        ? 'Create your PetPal account'
                        : 'Welcome to PetPal',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to automatically see your households and activity.',
                    textAlign: TextAlign.center,
                  ),
                  if (widget.startupError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.startupError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  if (creatingAccount) ...[
                    TextField(
                      controller: username,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  if (creatingAccount) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Re-type password',
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (notice != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      notice!,
                      style: const TextStyle(color: Color(0xFF147D70)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : creatingAccount
                          ? 'Create account'
                          : 'Sign in',
                    ),
                  ),
                  if (!creatingAccount && !widget.localMode) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: busy ? null : continueWithSso,
                      icon: const Icon(Icons.login),
                      label: const Text('Continue with Google SSO'),
                    ),
                  ],
                  if (needsConfirmation)
                    TextButton(
                      onPressed: busy ? null : resendConfirmation,
                      child: const Text('Resend confirmation email'),
                    ),
                  TextButton(
                    onPressed:
                        busy
                            ? null
                            : () => setState(() {
                              creatingAccount = !creatingAccount;
                              error = null;
                              notice = null;
                              needsConfirmation = false;
                            }),
                    child: Text(
                      creatingAccount
                          ? 'Already have an account? Sign in'
                          : 'New to PetPal? Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class FriendlyAuthError {
  final String message;
  final bool needsConfirmation;
  const FriendlyAuthError(this.message, {this.needsConfirmation = false});
}

FriendlyAuthError friendlyAuthError(
  AuthException exception, [
  bool creatingAccount = false,
]) {
  final message = exception.message.toLowerCase();
  final status = exception.statusCode;

  if (message.contains('email not confirmed') ||
      message.contains('email_not_confirmed')) {
    return const FriendlyAuthError(
      'Your email has not been confirmed yet. Check your inbox and spam folder, click the confirmation link, then sign in again.',
      needsConfirmation: true,
    );
  }
  if (message.contains('invalid login credentials') ||
      message.contains('user not found') ||
      message.contains('invalid email or password')) {
    return const FriendlyAuthError(
      'We could not sign you in. Check your email and password, or choose “Create an account” if you do not have an account yet.',
    );
  }
  if (message.contains('already registered') ||
      message.contains('already exists') ||
      message.contains('user already')) {
    return const FriendlyAuthError(
      'An account may already exist for this email. Try signing in instead, or use password recovery.',
    );
  }
  if (message.contains('password') &&
      (message.contains('weak') || message.contains('short'))) {
    return const FriendlyAuthError(
      'Choose a stronger password with at least 6 characters.',
    );
  }
  if (status == '429' ||
      message.contains('rate limit') ||
      message.contains('too many')) {
    return const FriendlyAuthError(
      'Too many attempts. Wait a few minutes before trying again.',
    );
  }
  if (message.contains('network') || message.contains('connection')) {
    return const FriendlyAuthError(
      'We could not connect to PetPal. Check your internet connection and try again.',
    );
  }
  return FriendlyAuthError(
    creatingAccount
        ? 'We could not create the account. Check your details and try again.'
        : 'We could not sign you in. Check your details and try again.',
  );
}

class Home extends StatefulWidget {
  final PetPalStore store;
  final String? currentUserLabel;
  final VoidCallback? onSignOut;
  const Home({
    super.key,
    required this.store,
    this.currentUserLabel,
    this.onSignOut,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  PetPalStore get s => widget.store;
  int tab = 0;
  DateTime day = DateUtils.dateOnly(DateTime.now());
  String? petFilter;
  Timer? timer;
  final Set<String> reminded = {};
  @override
  void initState() {
    super.initState();
    if (widget.currentUserLabel != null) {
      s.setCurrentUser(widget.currentUserLabel!);
    }
    s.addListener(refresh);
    timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => checkReminders(),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    s.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> householdPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Switch household',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ...s.households.map(
                    (h) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.home_work_outlined),
                      title: Text(h['name'] as String),
                      subtitle: Text(
                        '${(h['members'] as List?)?.length ?? 0} members · ${(h['pets'] as List?)?.length ?? 0} pets',
                      ),
                      trailing:
                          h['id'] == s.activeHouseholdId
                              ? const Icon(Icons.check, color: teal)
                              : null,
                      onTap: () async {
                        await s.switchHousehold(h['id'] as String);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_home_work_outlined),
                    title: const Text('Create another household'),
                    onTap: () {
                      Navigator.pop(ctx);
                      householdForm();
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> householdForm() async {
    final name = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Create household'),
            content: TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Household name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty),
                child: const Text('Create'),
              ),
            ],
          ),
    );
    if (created == true) {
      await s.createHousehold(name.text);
      message('Household created.');
    }
    name.dispose();
  }

  void accountMenu(String choice) {
    if (choice == 'households') {
      householdPicker();
    } else if (choice == 'create') {
      householdForm();
    } else if (choice == 'signout') {
      widget.onSignOut?.call();
    }
  }

  void checkReminders() {
    if (!s.reminders) return;
    final now = DateTime.now();
    for (final t in s.forDay(now)) {
      final key = '${t['id']}-${dayKey(now)}';
      final parts = (t['time'] as String).split(':');
      final due = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      if (!s.done(t, now) &&
          !reminded.contains(key) &&
          now.difference(due).inMinutes >= 0 &&
          now.difference(due).inMinutes < 2) {
        reminded.add(key);
        message('Time for ${s.petName(t['petId'])}: ${t['title']}');
      }
    }
    refresh();
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Text(title),
              content: Text(body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
              ],
            ),
      ) ??
      false;
  Widget panel(Widget child, {Color color = Colors.white}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: ink.withValues(alpha: .06)),
    ),
    child: Material(color: Colors.transparent, child: child),
  );
  Widget heading(String title, String subtitle, {Widget? action}) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 16,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF58716E), fontSize: 16),
            ),
          ],
        ),
        if (action != null) action,
      ],
    ),
  );
  Widget empty(String title, String detail, Widget action) => panel(
    Column(
      children: [
        const Icon(Icons.pets_rounded, size: 58, color: teal),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        action,
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (s.loadFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('PetPal')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.error ?? 'Unable to load saved data'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: s.load,
                  child: const Text('Retry loading'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final content = [today, pets, health, household][tab]();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: teal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.pets_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text('PetPal', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PopupMenuButton<String>(
              tooltip: 'Account and households',
              onSelected: accountMenu,
              itemBuilder:
                  (_) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      value: 'account',
                      child: Text(
                        s.currentUserName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'households',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.home_work_outlined),
                        title: Text('Switch household'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'create',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.add_home_work_outlined),
                        title: Text('Create household'),
                      ),
                    ),
                    if (widget.onSignOut != null)
                      const PopupMenuItem(
                        value: 'signout',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.logout),
                          title: Text('Sign out'),
                        ),
                      ),
                  ],
              child: Chip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(s.currentUserName),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide)
            SizedBox(
              width: 220,
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  ...List.generate(
                    4,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      child: ListTile(
                        selected: tab == i,
                        selectedTileColor: const Color(0xFFDDEFE9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(navIcons[i]),
                        title: Text(navLabels[i]),
                        onTap: () => setState(() => tab = i),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'A little care.\nA happier pet.',
                      style: TextStyle(
                        color: teal,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(wide ? 32 : 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (s.error != null)
                        panel(
                          Column(
                            children: [
                              Text(
                                s.error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                              TextButton(
                                onPressed: s.save,
                                child: const Text('Retry saving'),
                              ),
                            ],
                          ),
                        ),
                      content,
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          wide
              ? null
              : NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: List.generate(
                  4,
                  (i) => NavigationDestination(
                    icon: Icon(navIcons[i]),
                    label: navLabels[i],
                  ),
                ),
              ),
    );
  }

  static const navIcons = [
    Icons.space_dashboard_outlined,
    Icons.pets_outlined,
    Icons.favorite_border_rounded,
    Icons.people_outline_rounded,
  ];
  static const navLabels = ['Today', 'My pets', 'Health', 'Household'];
  String dateLabel(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget today() {
    final tasks =
        s
            .forDay(day)
            .where((t) => petFilter == null || t['petId'] == petFilter)
            .toList();
    final done = tasks.where((t) => s.done(t, day)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'Care starts here.',
          'One place for every little responsibility.',
          action: FilledButton.icon(
            onPressed: s.pets.isEmpty ? null : () => taskForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add task'),
          ),
        ),
        if (s.pets.isEmpty)
          empty(
            'Meet your new care companion',
            'Add your first pet to start planning their day.',
            Column(
              children: [
                FilledButton.icon(
                  onPressed: () => petForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add your first pet'),
                ),
                TextButton(
                  onPressed: s.demo,
                  child: const Text('Explore with a sample pet'),
                ),
              ],
            ),
          )
        else ...[
          panel(
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'THE DAILY CHECK-IN',
                        style: TextStyle(
                          color: Color(0xFFACE2D4),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tasks.isEmpty
                            ? 'A fresh start.'
                            : done == tasks.length
                            ? 'All cared for.'
                            : '$done of ${tasks.length} tasks done',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Small moments. Happy, healthy pets.',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: tasks.isEmpty ? 0 : done / tasks.length,
                          color: const Color(0xFFC8EF84),
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                const Icon(
                  Icons.pets_rounded,
                  size: 58,
                  color: Color(0xFFC8EF84),
                ),
              ],
            ),
            color: ink,
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed:
                    () => setState(
                      () => day = DateTime(day.year, day.month, day.day - 1),
                    ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => day = picked);
                  },
                  child: Text(
                    dateLabel(day),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed:
                    () => setState(
                      () => day = DateTime(day.year, day.month, day.day + 1),
                    ),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed:
                    () => setState(
                      () => day = DateUtils.dateOnly(DateTime.now()),
                    ),
                child: const Text('Today'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All pets'),
                selected: petFilter == null,
                onSelected: (_) => setState(() => petFilter = null),
              ),
              ...s.pets.map(
                (p) => ChoiceChip(
                  label: Text(p['name']),
                  selected: petFilter == p['id'],
                  onSelected: (_) => setState(() => petFilter = p['id']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (tasks.isEmpty)
            empty(
              'A clear schedule',
              'Add feeding, walks, grooming, or medication tasks.',
              FilledButton(
                onPressed: () => taskForm(),
                child: const Text('Plan a task'),
              ),
            ),
          ...tasks.map(taskTile),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Reminders appear while PetPal is open. Household activity is saved on this device.',
              style: TextStyle(color: Color(0xFF58716E), fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget taskTile(Map<String, dynamic> t) {
    final complete = s.completion(t, day);
    final categoryIndex = categories.indexOf(t['category']);
    final future = day.isAfter(DateUtils.dateOnly(DateTime.now()));
    final due = DateTime.parse('${dayKey(day)}T${t['time']}:00');
    final late = complete == null && due.isBefore(DateTime.now());
    return panel(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:
                  complete != null
                      ? const Color(0xFFE4F2E8)
                      : const Color(0xFFFFF0D7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              categoryIcons[categoryIndex < 0 ? 4 : categoryIndex],
              color: complete != null ? teal : const Color(0xFF96631C),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t['title'],
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    decoration:
                        complete != null ? TextDecoration.lineThrough : null,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${s.petName(t['petId'])} · ${t['time']} · ${t['assignee']}',
                  style: const TextStyle(fontSize: 14),
                ),
                if ((t['notes'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(t['notes']),
                  ),
                const SizedBox(height: 8),
                Text(
                  complete != null
                      ? 'Done by ${complete['by']} · ${TimeOfDay.fromDateTime(DateTime.parse(complete['at'])).format(context)}'
                      : '${t['daily'] ? 'Daily' : 'One time'}${late ? ' · Overdue' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        complete != null
                            ? teal
                            : late
                            ? const Color(0xFFAC572B)
                            : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton.filledTonal(
                tooltip:
                    complete != null
                        ? 'Undo completion'
                        : future
                        ? 'Available on scheduled day'
                        : 'Mark complete',
                onPressed:
                    future
                        ? null
                        : () async {
                          if (complete != null) {
                            await s.undo(t, day);
                          } else {
                            await s.complete(t, day);
                          }
                        },
                icon: Icon(
                  complete != null ? Icons.check_circle : Icons.circle_outlined,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Task options',
                onSelected: (v) async {
                  if (v == 'edit') {
                    taskForm(existing: t);
                  } else if (await confirm(
                    'Delete task?',
                    'This removes the schedule. Completion history is kept.',
                  )) {
                    s.tasks.remove(t);
                    await s.save();
                  }
                },
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit task')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete task'),
                      ),
                    ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget pets() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Your little family',
        'Every pet, their own care plan.',
        action: FilledButton.icon(
          onPressed: () => petForm(),
          icon: const Icon(Icons.add),
          label: const Text('Add pet'),
        ),
      ),
      if (s.pets.isEmpty)
        empty(
          'No pets yet',
          'Start with a name and a few details.',
          FilledButton(
            onPressed: () => petForm(),
            child: const Text('Add pet'),
          ),
        ),
      ...s.pets.map(
        (p) => panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
             (p['photo'] as String? ?? '').isNotEmpty
    		? petPhoto(p['photo'] as String?)
    		: CircleAvatar(  
                    radius: 30,
                    backgroundColor: const Color(0xFFE6EFDC),
                    child: Text(
                      p['species'] == 'Cat'
                          ? '🐱'
                          : p['species'] == 'Dog'
                          ? '🐶'
                          : '🐾',
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['name'],
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          '${p['species']} · ${p['breed'].toString().isEmpty ? 'Breed not set' : p['breed']}',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit pet',
                    onPressed: () => petForm(existing: p),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const Divider(height: 32),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  Text(
                    'Birthday: ${p['birthday'].toString().isEmpty ? 'Not set' : p['birthday']}',
                  ),
                  Text(
                    'Weight: ${p['weight'].toString().isEmpty ? 'Not set' : p['weight']}',
                  ),
                ],
              ),
              if (p['notes'].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(p['notes']),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        tab = 0;
                        petFilter = p['id'];
                      });
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: const Text('Care schedule'),
                  ),
                  TextButton.icon(
                    onPressed: () => recordForm(petId: p['id']),
                    icon: const Icon(Icons.add),
                    label: const Text('Health record'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget health() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Health & records',
        'Keep the details close at hand.',
        action: FilledButton.icon(
          onPressed: s.pets.isEmpty ? null : () => recordForm(),
          icon: const Icon(Icons.add),
          label: const Text('Add record'),
        ),
      ),
      panel(
        const Row(
          children: [
            Icon(Icons.folder_open_rounded, color: teal),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Vet visits, vaccinations, medications, and notes. This device-only prototype is not a replacement for your vet’s records.',
              ),
            ),
          ],
        ),
      ),
      if (s.records.isEmpty)
        empty(
          'Their story starts here',
          'Add a vet visit, vaccination, or health note.',
          FilledButton(
            onPressed: s.pets.isEmpty ? () => petForm() : () => recordForm(),
            child: Text(
              s.pets.isEmpty ? 'Add a pet first' : 'Add health record',
            ),
          ),
        ),
      ...(s.records.toList()..sort(
            (a, b) => (b['date'] as String).compareTo(a['date'] as String),
          ))
          .map(
            (r) => panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite_border, color: teal),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          r['title'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit record',
                        onPressed: () => recordForm(existing: r),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${s.petName(r['petId'])} · ${r['type']} · ${r['date']}',
                  ),
                  if (r['provider'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Provider: ${r['provider']}'),
                    ),
                  if (r['notes'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(r['notes']),
                    ),
                ],
              ),
            ),
          ),
    ],
  );
  Widget household() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      heading(
        'Better, together.',
        'Know who is taking care of what.',
        action: FilledButton.icon(
          onPressed: memberForm,
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add member'),
        ),
      ),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your household',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage the people who share this household. Use the profile menu above to switch households.',
            ),
            const SizedBox(height: 12),
            ...s.members.map(
              (m) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFDDEFE9),
                  child: Text(m.substring(0, 1).toUpperCase()),
                ),
                title: Text(m),
                subtitle: Text(
                  '${s.tasks.where((t) => t['assignee'] == m).length} assigned tasks',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    m == s.activeMember
                        ? const Chip(label: Text('Active'))
                        : TextButton(
                          onPressed: () {
                            s.activeMember = m;
                            s.save();
                          },
                          child: const Text('Switch'),
                        ),
                    if (m != s.currentUserName)
                      IconButton(
                        tooltip: 'Remove $m',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: () async {
                          final confirmed = await confirm(
                            'Remove $m?',
                            'Their assigned tasks will be reassigned to the remaining household owner.',
                          );
                          if (confirmed) {
                            await s.removeMember(m);
                            message('$m was removed from the household.');
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('In-app reminders'),
              subtitle: const Text(
                'Show due-task alerts while the app is open.',
              ),
              value: s.reminders,
              onChanged: (v) {
                s.reminders = v;
                s.save();
              },
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: s.export()));
                message('Data copied as JSON. Keep a backup somewhere safe.');
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy data backup'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text('Recent care', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      if (s.history.isEmpty)
        panel(
          const Text(
            'Completed tasks will appear here with who did them and when.',
          ),
        ),
      ...s.history.reversed
          .take(30)
          .map(
            (h) => panel(
              Row(
                children: [
                  const Icon(Icons.check_circle, color: teal),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${h['by']} completed ${h['title']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text('${h['pet']} · ${h['day']}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
  Future<void> form({
    required String title,
    required List<Widget> Function(void Function(void Function())) fields,
    required Future<void> Function() onSave,
    Future<void> Function()? onDelete,
  }) async {
    final key = GlobalKey<FormState>();
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, update) => AlertDialog(
                  title: Text(title),
                  content: SizedBox(
                    width: 460,
                    child: SingleChildScrollView(
                      child: Form(
                        key: key,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children:
                              fields(update)
                                  .map(
                                    (w) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: w,
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    if (onDelete != null)
                      TextButton(
                        onPressed:
                            saving
                                ? null
                                : () async {
                                  if (await confirm(
                                    'Delete this item?',
                                    'This cannot be undone. Deleting a pet also removes its tasks and health records.',
                                  )) {
                                    await onDelete();
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  }
                                },
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    TextButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed:
                          saving
                              ? null
                              : () async {
                                if (!key.currentState!.validate()) return;
                                update(() => saving = true);
                                await onSave();
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                      child: Text(saving ? 'Saving…' : 'Save'),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget field(
    TextEditingController c,
    String label, {
    bool required = false,
    int lines = 1,
    String? hint,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: c,
    maxLines: lines,
    maxLength: lines > 1 ? 2000 : 100,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
    ),
    validator:
        validator ??
        (v) =>
            required && (v == null || v.trim().isEmpty)
                ? 'Please enter $label'
                : null,
  );
  Widget choice(
    String label,
    String value,
    List<String> options,
    void Function(String) change,
  ) => DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items:
        options
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(v, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
    onChanged: (v) {
      if (v != null) change(v);
    },
  );
  Future<void> petForm({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name']);
    final breed = TextEditingController(text: existing?['breed']);
    final birthday = TextEditingController(text: existing?['birthday']);
    final weight = TextEditingController(text: existing?['weight']);
    final notes = TextEditingController(text: existing?['notes']);
    String species = existing?['species'] ?? 'Dog';
    String photo = existing?['photo'] as String? ?? '';
    String? photoError;
    bool choosingPhoto = false;
    bool formOpen = true;
    await form(
      title: existing == null ? 'Meet your pet' : 'Edit pet',
      fields:
          (update) => [
	    Center(child: petPhoto(photo, radius: 48)),
            const SizedBox(height: 12),
OutlinedButton.icon(
  icon: const Icon(Icons.add_photo_alternate_outlined),
  label: Text(choosingPhoto ? 'Opening photos…' : 'Choose photo'),
  onPressed: choosingPhoto
      ? null
      : () async {
          update(() {
            choosingPhoto = true;
            photoError = null;
          });

          try {
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 600,
              maxHeight: 600,
              imageQuality: 75,
            );

            if (picked == null || !formOpen || !mounted) return;

            final bytes = await picked.readAsBytes();
            if (!formOpen || !mounted) return;

            if (bytes.length > 500 * 1024) {
              update(() {
                photoError = 'Choose a photo under 500 KB.';
              });
              return;
            }

            update(() {
              photo = base64Encode(bytes);
            });
          } catch (_) {
            if (formOpen && mounted) {
              update(() {
                photoError = 'Could not open that photo. Try a JPG or PNG.';
              });
            }
          } finally {
            if (formOpen && mounted) {
              update(() => choosingPhoto = false);
            }
          }
        },
),
if (photo.isNotEmpty)
  TextButton.icon(
    onPressed: () => update(() {
      photo = '';
      photoError = null;
    }),
    icon: const Icon(Icons.delete_outline),
    label: const Text('Remove photo'),
  ),
if (photoError != null)
  Text(
    photoError!,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  ),
            field(name, 'Name', required: true),
            choice('Species', species, [
              'Dog',
              'Cat',
              'Bird',
              'Rabbit',
              'Other',
            ], (v) => update(() => species = v)),
            field(breed, 'Breed'),
            TextFormField(
              controller: birthday,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Birthday (optional)',
                suffixIcon: IconButton(
                  tooltip: 'Clear birthday',
                  onPressed: birthday.clear,
                  icon: const Icon(Icons.clear),
                ),
              ),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(birthday.text) ?? DateTime.now(),
                  firstDate: DateTime(1970),
                  lastDate: DateTime.now(),
                );
                if (value != null) birthday.text = dayKey(value);
              },
            ),
            field(weight, 'Weight', hint: 'For example, 28 kg'),
            field(notes, 'Care notes', lines: 3),
          ],
      onSave: () async {
        final data = {
          'id': existing?['id'] ?? newId(),
          'name': name.text.trim(),
          'species': species,
	  'photo': photo,
          'breed': breed.text.trim(),
          'birthday': birthday.text,
          'weight': weight.text.trim(),
          'notes': notes.text.trim(),
        };
        if (existing != null) {
          existing.addAll(data);
        } else {
          s.pets.add(data);
        }
        await s.save();
      },
      onDelete:
          existing == null
              ? null
              : () async {
                if (petFilter == existing['id']) petFilter = null;
                await s.removePet(existing['id']);
              },
    );
    formOpen = false;
    await disposeControllersAfterDialog([name, breed, birthday, weight, notes]);
  }

  /// A dialog can still be finishing its close animation after showDialog
  /// returns. Dispose controllers after the form widgets are fully unmounted.
  Future<void> disposeControllersAfterDialog(
    Iterable<TextEditingController> controllers,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  Future<void> taskForm({Map<String, dynamic>? existing}) async {
    if (s.pets.isEmpty) return;
    final title = TextEditingController(text: existing?['title']);
    final notes = TextEditingController(text: existing?['notes']);
    String petId = existing?['petId'] ?? petFilter ?? s.pets.first['id'];
    String category = existing?['category'] ?? 'Feeding';
    String assignee = existing?['assignee'] ?? s.activeMember;
    bool daily = existing?['daily'] ?? true;
    DateTime start = DateTime.tryParse(existing?['date'] ?? '') ?? day;
    final parts = (existing?['time'] as String? ?? '08:00').split(':');
    TimeOfDay time = TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
    await form(
      title: existing == null ? 'Plan a care task' : 'Edit care task',
      fields:
          (update) => [
            field(
              title,
              'Task name',
              required: true,
              hint: 'For example, breakfast',
            ),
            DropdownButtonFormField<String>(
              value: petId,
              decoration: const InputDecoration(labelText: 'Pet'),
              items:
                  s.pets
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p['id'],
                          child: Text(p['name']),
                        ),
                      )
                      .toList(),
              onChanged: (v) => update(() => petId = v!),
            ),
            choice(
              'Care type',
              category,
              categories,
              (v) => update(() => category = v),
            ),
            choice(
              'Assigned to',
              assignee,
              s.members,
              (v) => update(() => assignee = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text('${daily ? 'Starts' : 'Date'}: ${dateLabel(start)}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: start,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) update(() => start = picked);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(time.format(context)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time,
                );
                if (picked != null) update(() => time = picked);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat every day'),
              value: daily,
              onChanged: (v) => update(() => daily = v),
            ),
            field(
              notes,
              'Instructions',
              lines: 3,
              hint: 'Amount, route, or instructions from your vet',
            ),
          ],
      onSave: () async {
        final data = {
          'id': existing?['id'] ?? newId(),
          'petId': petId,
          'title': title.text.trim(),
          'category': category,
          'assignee': assignee,
          'daily': daily,
          'date': dayKey(start),
          'time':
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          'notes': notes.text.trim(),
        };
        if (existing != null) {
          existing.addAll(data);
        } else {
          s.tasks.add(data);
        }
        await s.save();
      },
    );
    await disposeControllersAfterDialog([title, notes]);
  }

  Future<void> recordForm({
    String? petId,
    Map<String, dynamic>? existing,
  }) async {
    if (s.pets.isEmpty) return;
    String selectedPet = existing?['petId'] ?? petId ?? s.pets.first['id'];
    String type = existing?['type'] ?? 'Vet visit';
    DateTime date =
        DateTime.tryParse(existing?['date'] ?? '') ?? DateTime.now();
    final title = TextEditingController(text: existing?['title']);
    final provider = TextEditingController(text: existing?['provider']);
    final notes = TextEditingController(text: existing?['notes']);
    await form(
      title: existing == null ? 'Add health record' : 'Edit health record',
      fields:
          (update) => [
            field(title, 'Record title', required: true),
            DropdownButtonFormField<String>(
              value: selectedPet,
              decoration: const InputDecoration(labelText: 'Pet'),
              items:
                  s.pets
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p['id'],
                          child: Text(p['name']),
                        ),
                      )
                      .toList(),
              onChanged: (v) => update(() => selectedPet = v!),
            ),
            choice('Record type', type, [
              'Vet visit',
              'Vaccination',
              'Medication',
              'Allergy',
              'Other',
            ], (v) => update(() => type = v)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(dateLabel(date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(1970),
                  lastDate: DateTime(2100),
                );
                if (picked != null) update(() => date = picked);
              },
            ),
            field(provider, 'Vet or clinic'),
            field(notes, 'Details', lines: 4),
          ],
      onSave: () async {
        final data = {
          'id': existing?['id'] ?? newId(),
          'petId': selectedPet,
          'title': title.text.trim(),
          'type': type,
          'date': dayKey(date),
          'provider': provider.text.trim(),
          'notes': notes.text.trim(),
        };
        if (existing != null) {
          existing.addAll(data);
        } else {
          s.records.add(data);
        }
        await s.save();
      },
      onDelete:
          existing == null
              ? null
              : () async {
                s.records.remove(existing);
                await s.save();
              },
    );
    await disposeControllersAfterDialog([title, provider, notes]);
  }

  Future<void> memberForm() async {
    final name = TextEditingController();
    await form(
      title: 'Add household member',
      fields:
          (_) => [
            field(
              name,
              'Name',
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Enter a name';
                }
                if (s.members.any(
                  (m) => m.toLowerCase() == v.trim().toLowerCase(),
                )) {
                  return 'That name is already in your household';
                }
                return null;
              },
            ),
          ],
      onSave: () async {
        s.members.add(name.text.trim());
        await s.save();
      },
    );
    await disposeControllersAfterDialog([name]);
  }
}
