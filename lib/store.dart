import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

class PetPalStore extends ChangeNotifier {
  final SharedPreferencesAsync prefs;
  PetPalStore({SharedPreferencesAsync? preferences})
    : prefs = preferences ?? SharedPreferencesAsync();
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
    } catch (_) {
      loadFailed = true;
      error = 'Saved data could not be loaded. Retry before making changes.';
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
        error = null;
      } catch (_) {
        error = 'Could not save changes. Keep the app open and try again.';
      }
      notifyListeners();
    });
    notifyListeners();
    return _queue;
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
