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
        pets = _list(data['pets']);
        tasks = _list(data['tasks']);
        records = _list(data['records']);
        history = _list(data['history']);
        members = List<String>.from(data['members']);
        activeMember = data['activeMember'] as String;
        reminders = data['reminders'] as bool;
      }
    } catch (_) {
      loadFailed = true;
      error = 'Saved data could not be loaded. Retry before making changes.';
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  String export() => const JsonEncoder.withIndent('  ').convert({
    'pets': pets,
    'tasks': tasks,
    'records': records,
    'history': history,
    'members': members,
    'activeMember': activeMember,
    'reminders': reminders,
  });
  Future<void> save() {
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
    members = ['You', 'Housemate'];
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
        'assignee': 'You',
        'notes': '',
      });
    }
    await save();
  }
}
