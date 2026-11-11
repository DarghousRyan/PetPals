import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class PetPalStore extends ChangeNotifier {
  final SharedPreferencesAsync prefs;
  final SupabaseClient? remote;
  final Map<String, String> memberUserIds = {};
  PetPalStore({
    SharedPreferencesAsync? preferences,
    SupabaseClient? supabaseClient,
  }) : prefs = preferences ?? SharedPreferencesAsync(),
       remote = supabaseClient;
  List<Map<String, dynamic>> pets = [];
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> history = [];
  List<String> members = ['You'];
  String activeMember = 'You';
  String currentUserName = 'You';
  List<Map<String, dynamic>> households = [];
  String activeHouseholdId = 'default';
  bool reminders = true;
  String? error;
  bool loadFailed = false;
  Future<void> _queue = Future.value();

  Future<void> load() async {
    loadFailed = false;
    error = null;
    try {
      final raw = await prefs.getString('petpal.v1');
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        currentUserName = (data['currentUserName'] as String?) ?? 'You';
        final savedHouseholds = data['households'];
        if (savedHouseholds is List && savedHouseholds.isNotEmpty) {
          households = _list(savedHouseholds);
          activeHouseholdId =
              (data['activeHouseholdId'] as String?) ??
              households.first['id'] as String;
          _loadHousehold(activeHouseholdId);
        } else {
          // Migrate the original single-household prototype format.
          pets = _list(data['pets'] ?? const []);
          tasks = _list(data['tasks'] ?? const []);
          records = _list(data['records'] ?? const []);
          history = _list(data['history'] ?? const []);
          members = List<String>.from(data['members'] ?? ['You']);
          activeMember = (data['activeMember'] as String?) ?? 'You';
          reminders = (data['reminders'] as bool?) ?? true;
          households = [_snapshot(name: 'My household')];
          activeHouseholdId = households.first['id'] as String;
          _loadHousehold(activeHouseholdId);
        }
      }
      if (remote?.auth.currentUser != null) {
        await _loadRemote();
      }
    } catch (_) {
      loadFailed = true;
      error =
          remote?.auth.currentUser != null
              ? 'Online data could not be loaded. Check your connection and retry.'
              : 'Saved data could not be loaded. Retry before making changes.';
    }
    notifyListeners();
  }

  void setCurrentUser(String name) {
    if (name.trim().isEmpty) return;
    final normalized = name.trim();
    final previousName = currentUserName;
    currentUserName = normalized;
    final ownerIndex = members.indexOf(previousName);
    if (ownerIndex >= 0) {
      members[ownerIndex] = normalized;
    } else if (!members.contains(normalized)) {
      members.insert(0, normalized);
    }
    activeMember = normalized;
    if (households.isEmpty) {
      households = [_snapshot(name: 'My household')];
    } else {
      _syncActiveHousehold();
    }
    notifyListeners();
  }

  String get activeHouseholdName =>
      households.where((h) => h['id'] == activeHouseholdId).firstOrNull?['name']
          as String? ??
      'My household';

  void _loadHousehold(String id) {
    final household = households.where((h) => h['id'] == id).firstOrNull;
    if (household == null) return;
    pets = _list(household['pets'] ?? const []);
    tasks = _list(household['tasks'] ?? const []);
    records = _list(household['records'] ?? const []);
    history = _list(household['history'] ?? const []);
    members = List<String>.from(household['members'] ?? [currentUserName]);
    activeMember =
        (household['activeMember'] as String?) ?? currentUserName;
    reminders = (household['reminders'] as bool?) ?? true;
    if (!members.contains(currentUserName)) members.insert(0, currentUserName);
  }

  Map<String, dynamic> _snapshot({String? name}) => {
    'id': activeHouseholdId,
    'name': name ?? activeHouseholdName,
    'pets': pets,
    'tasks': tasks,
    'records': records,
    'history': history,
    'members': members,
    'activeMember': activeMember,
    'reminders': reminders,
  };

  void _syncActiveHousehold() {
    final index = households.indexWhere((h) => h['id'] == activeHouseholdId);
    final snapshot = _snapshot();
    if (index >= 0) {
      households[index] = snapshot;
    } else {
      households.add(snapshot);
    }
  }

  Future<void> switchHousehold(String id) async {
    if (id == activeHouseholdId || !households.any((h) => h['id'] == id)) {
      return;
    }
    _syncActiveHousehold();
    activeHouseholdId = id;
    _loadHousehold(id);
    await save();
  }

  Future<void> createHousehold(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) return;
    _syncActiveHousehold();
    final id = newId();
    activeHouseholdId = id;
    households.add({
      'id': id,
      'name': normalized,
      'pets': <Map<String, dynamic>>[],
      'tasks': <Map<String, dynamic>>[],
      'records': <Map<String, dynamic>>[],
      'history': <Map<String, dynamic>>[],
      'members': [currentUserName],
      'activeMember': currentUserName,
      'reminders': true,
    });
    _loadHousehold(id);
    await save();
  }

  Future<String> createInvitation({
    required String email,
    required String role,
  }) async {
    final client = remote;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Online sign-in is required to invite a member.');
    }
    final result = await client.rpc(
      'create_household_invitation',
      params: {
        'target_household_id': activeHouseholdId,
        'invited_email': email.trim(),
        'invited_role': role,
      },
    );
    final row = result is List ? result.first : result;
    return (row as Map)['invite_token'] as String;
  }

  Future<void> acceptInvitation({
    required String token,
    String displayName = '',
  }) async {
    final client = remote;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Online sign-in is required to accept an invitation.');
    }
    await client.rpc(
      'accept_household_invitation',
      params: {
        'invitation_token': token.trim(),
        'member_display_name': displayName.trim(),
      },
    );
    await _loadRemote();
    notifyListeners();
  }

  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  String export() => const JsonEncoder.withIndent('  ').convert({
    'currentUserName': currentUserName,
    'households': households,
    'activeHouseholdId': activeHouseholdId,
    'pets': pets,
    'tasks': tasks,
    'records': records,
    'history': history,
    'members': members,
    'activeMember': activeMember,
    'reminders': reminders,
  });
  Future<void> save() {
    _syncActiveHousehold();
    final snapshot = export();
    _queue = _queue.then((_) async {
      try {
        await prefs.setString('petpal.v1', snapshot);
        await _saveRemote();
        error = null;
      } catch (_) {
        error =
            remote?.auth.currentUser != null
                ? 'Could not sync changes online. Check your connection and try again.'
                : 'Could not save changes. Keep the app open and try again.';
      }
      notifyListeners();
    });
    notifyListeners();
    return _queue;
  }

  List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  String _timeValue(dynamic value) {
    final text = value?.toString() ?? '00:00';
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  Future<void> _loadRemote() async {
    final client = remote;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;

    final membershipRows = _rows(
      await client
          .from('household_members')
          .select('household_id,user_id,display_name,role')
          .eq('user_id', user.id)
          .eq('status', 'active'),
    );

    if (membershipRows.isEmpty) {
      // Give a new authenticated account one usable household. Existing local
      // prototype data is uploaded after the owner membership is created.
      final id = newId();
      await client.rpc(
        'create_household_with_owner',
        params: {
          'household_id': id,
          'household_name': 'My household',
          'owner_display_name': currentUserName,
        },
      );
      households = [
        _snapshot(name: 'My household')
          ..['id'] = id
          ..['members'] = [currentUserName],
      ];
      activeHouseholdId = id;
      memberUserIds[currentUserName] = user.id;
      await _saveRemote();
      await prefs.setString('petpal.v1', export());
      return;
    }

    final ids = membershipRows
        .map((row) => row['household_id'] as String)
        .toList();
    final householdRows = _rows(
      await client.from('households').select('id,name').inFilter('id', ids),
    );
    final loaded = <Map<String, dynamic>>[];
    for (final household in householdRows) {
      final householdId = household['id'] as String;
      final membersRows = _rows(
        await client
            .from('household_members')
            .select('user_id,display_name,role')
            .eq('household_id', householdId)
            .eq('status', 'active'),
      );
      final memberNames = <String>[];
      for (final member in membersRows) {
        final name = member['display_name'] as String;
        memberNames.add(name);
        memberUserIds[name] = member['user_id'] as String;
      }

      final petsRows = _rows(
        await client.from('pets').select().eq('household_id', householdId),
      );
      final petsForHousehold = petsRows
          .map(
            (pet) => {
              'id': pet['id'],
              'name': pet['name'],
              'species': pet['species'] ?? '',
              'breed': pet['breed'] ?? '',
              'birthday': pet['birthday']?.toString() ?? '',
              'weight': pet['weight'] ?? '',
              'notes': pet['notes'] ?? '',
              'photo': pet['photo'] ?? '',
            },
          )
          .toList();
      final petNames = {
        for (final pet in petsForHousehold) pet['id'] as String: pet['name'] as String,
      };

      final taskRows = _rows(
        await client.from('tasks').select().eq('household_id', householdId),
      );
      final tasksForHousehold = taskRows
          .map(
            (task) {
              final assignedId = task['assigned_to'] as String?;
              return {
                'id': task['id'],
                'petId': task['pet_id'],
                'title': task['title'],
                'category': task['category'] ?? 'Other',
                'time': _timeValue(task['scheduled_time']),
                'date': task['scheduled_date'].toString(),
                'daily': task['repeats_daily'] ?? false,
                'assignee':
                    assignedId == null
                        ? currentUserName
                        : memberUserIds[assignedId] ?? currentUserName,
                'notes': task['care_notes'] ?? '',
              };
            },
          )
          .toList();
      final taskNames = {
        for (final task in tasksForHousehold) task['id'] as String: task['title'] as String,
      };

      final completionRows = _rows(
        await client
            .from('task_completions')
            .select()
            .eq('household_id', householdId),
      );
      final historyForHousehold = completionRows
          .map(
            (completion) => {
              'id': completion['id'],
              'taskId': completion['task_id'],
              'title':
                  taskNames[completion['task_id']] ??
                  completion['task_id'].toString(),
              'pet': petNames[completion['pet_id']] ?? 'Removed pet',
              'day': completion['care_day'].toString(),
              'by': completion['completed_by_name'],
              'at': completion['completed_at'],
            },
          )
          .toList();

      final recordRows = _rows(
        await client
            .from('health_records')
            .select()
            .eq('household_id', householdId),
      );
      final recordsForHousehold = recordRows
          .map(
            (record) => {
              'id': record['id'],
              'petId': record['pet_id'],
              'title': record['title'],
              'type': record['record_type'] ?? 'Other',
              'date': record['record_date'].toString(),
              'provider': record['provider'] ?? '',
              'notes': record['notes'] ?? '',
            },
          )
          .toList();

      loaded.add({
        'id': householdId,
        'name': household['name'],
        'pets': petsForHousehold,
        'tasks': tasksForHousehold,
        'records': recordsForHousehold,
        'history': historyForHousehold,
        'members': memberNames,
        'activeMember': memberNames.contains(currentUserName)
            ? currentUserName
            : memberNames.first,
        'reminders': true,
      });
    }

    households = loaded;
    if (!households.any((household) => household['id'] == activeHouseholdId)) {
      activeHouseholdId = households.first['id'] as String;
    }
    _loadHousehold(activeHouseholdId);
    await prefs.setString('petpal.v1', export());
  }

  Future<void> _saveRemote() async {
    final client = remote;
    final user = client?.auth.currentUser;
    if (client == null || user == null || households.isEmpty) return;
    final householdId = activeHouseholdId;
    await client.from('households').upsert({
      'id': householdId,
      'name': activeHouseholdName,
      'created_by': user.id,
    });

    final memberRows = <Map<String, dynamic>>[];
    for (final member in members) {
      final memberId = memberUserIds[member] ??
          (member == currentUserName ? user.id : null);
      if (memberId == null) continue;
      memberUserIds[member] = memberId;
      memberRows.add({
        'household_id': householdId,
        'user_id': memberId,
        'display_name': member,
        'role': member == currentUserName ? 'admin' : 'member',
        'status': 'active',
      });
    }
    if (memberRows.isNotEmpty) {
      await client.from('household_members').upsert(memberRows);
    }

    if (pets.isNotEmpty) {
      await client.from('pets').upsert(
        pets
            .map(
              (pet) => {
                'id': pet['id'],
                'household_id': householdId,
                'name': pet['name'],
                'species': pet['species'] ?? '',
                'breed': pet['breed'] ?? '',
                'birthday': (pet['birthday'] as String).isEmpty
                    ? null
                    : pet['birthday'],
                'weight': pet['weight'] ?? '',
                'notes': pet['notes'] ?? '',
                'photo': pet['photo'] ?? '',
              },
            )
            .toList(),
      );
    }
    if (tasks.isNotEmpty) {
      await client.from('tasks').upsert(
        tasks
            .map(
              (task) => {
                'id': task['id'],
                'household_id': householdId,
                'pet_id': task['petId'],
                'title': task['title'],
                'category': task['category'] ?? 'Other',
                'care_notes': task['notes'] ?? '',
                'scheduled_time': '${task['time']}:00',
                'scheduled_date': task['date'],
                'repeats_daily': task['daily'] ?? false,
                'assigned_to': memberUserIds[task['assignee']],
                'created_by': user.id,
              },
            )
            .toList(),
      );
    }
    if (history.isNotEmpty) {
      await client.from('task_completions').upsert(
        history
            .map(
              (completion) => {
                'id': completion['id'],
                'household_id': householdId,
                'task_id': completion['taskId'],
                'pet_id': tasks
                    .where((task) => task['id'] == completion['taskId'])
                    .firstOrNull?['petId'],
                'care_day': completion['day'],
                'completed_by': memberUserIds[completion['by']] ?? user.id,
                'completed_by_name': completion['by'],
                'completed_at': completion['at'],
              },
            )
            .where((completion) => completion['pet_id'] != null)
            .toList(),
      );
    }
    if (records.isNotEmpty) {
      await client.from('health_records').upsert(
        records
            .map(
              (record) => {
                'id': record['id'],
                'household_id': householdId,
                'pet_id': record['petId'],
                'title': record['title'],
                'record_type': record['type'] ?? 'Other',
                'record_date': record['date'],
                'provider': record['provider'] ?? '',
                'notes': record['notes'] ?? '',
                'created_by': user.id,
              },
            )
            .toList(),
      );
    }
  }

  String petName(String id) =>
      pets.where((p) => p['id'] == id).firstOrNull?['name'] as String? ??
      'Removed pet';
  bool done(Map<String, dynamic> task, DateTime day) =>
      history.any((h) => h['taskId'] == task['id'] && h['day'] == dayKey(day));
  Map<String, dynamic>? completion(Map<String, dynamic> task, DateTime day) =>
      history
          .where((h) => h['taskId'] == task['id'] && h['day'] == dayKey(day))
          .firstOrNull;
  List<Map<String, dynamic>> forDay(DateTime day) {
    final key = dayKey(day);
    return tasks
        .where(
          (t) =>
              t['date'] == key ||
              (t['daily'] == true && (t['date'] as String).compareTo(key) <= 0),
        )
        .toList()
      ..sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));
  }

  Future<bool> complete(Map<String, dynamic> task, DateTime day) async {
    if (done(task, day)) return false;
    history.add({
      'id': newId(),
      'taskId': task['id'],
      'title': task['title'],
      'pet': petName(task['petId']),
      'day': dayKey(day),
      'by': activeMember,
      'at': DateTime.now().toIso8601String(),
    });
    await save();
    return true;
  }

  Future<void> undo(Map<String, dynamic> task, DateTime day) async {
    history.removeWhere(
      (h) => h['taskId'] == task['id'] && h['day'] == dayKey(day),
    );
    await save();
  }

  Future<void> removePet(String id) async {
    pets.removeWhere((p) => p['id'] == id);
    tasks.removeWhere((t) => t['petId'] == id);
    records.removeWhere((r) => r['petId'] == id);
    await save();
  }

  Future<bool> removeMember(String member) async {
    // Keep the local owner profile so the household always has an owner.
    if (member == currentUserName || !members.contains(member)) return false;

    members.remove(member);
    final fallback = members.isNotEmpty ? members.first : currentUserName;
    for (final task in tasks) {
      if (task['assignee'] == member) task['assignee'] = fallback;
    }
    if (activeMember == member) activeMember = fallback;
    await save();
    return true;
  }

  Future<void> demo() async {
    if (pets.isNotEmpty) return;
    pets.add({
      'id': 'demo-milo',
      'name': 'Milo',
      'species': 'Dog',
      'breed': 'Golden retriever',
      'birthday': '2022-05-12',
      'weight': '28 kg',
      'notes': 'Sample pet — replace with your own details.',
    });
    members = [currentUserName, 'Housemate'];
    for (final entry in [
      ['Breakfast', 'Feeding', '08:00'],
      ['Morning walk', 'Walking', '09:00'],
      ['Brush coat', 'Grooming', '17:00'],
      ['Dinner', 'Feeding', '18:00'],
    ]) {
      tasks.add({
        'id': '${newId()}-${entry[0]}',
        'petId': 'demo-milo',
        'title': entry[0],
        'category': entry[1],
        'time': entry[2],
        'date': dayKey(DateTime.now()),
        'daily': true,
        'assignee': currentUserName,
        'notes': '',
      });
    }
    await save();
  }
}
