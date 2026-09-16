import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/store.dart';

class MemoryStore extends PetPalStore {
  @override
  Future<void> save() async {
    notifyListeners();
  }
}

void main() {
  late MemoryStore store;
  final today = DateTime(2026, 9, 9);
  setUp(() {
    store = MemoryStore();
    store.pets.add({'id': 'p', 'name': 'Milo'});
    store.tasks.add({
      'id': 't',
      'petId': 'p',
      'title': 'Breakfast',
      'date': '2026-09-09',
      'time': '08:00',
      'daily': true,
    });
  });
  test('daily care starts on its start date and repeats next day', () {
    expect(store.forDay(today.subtract(const Duration(days: 1))), isEmpty);
    expect(store.forDay(today), hasLength(1));
    expect(store.forDay(today.add(const Duration(days: 1))), hasLength(1));
  });
  test('completion is idempotent and attributed to active caregiver', () async {
    store.activeMember = 'Ryan';
    final task = store.tasks.first;
    expect(await store.complete(task, today), isTrue);
    expect(await store.complete(task, today), isFalse);
    expect(store.history, hasLength(1));
    expect(store.history.single['by'], 'Ryan');
    expect(store.done(task, today.add(const Duration(days: 1))), isFalse);
    await store.undo(task, today);
    expect(store.done(task, today), isFalse);
  });
  test('one-time task is only on its scheduled date', () {
    store.tasks.first['daily'] = false;
    expect(store.forDay(today), hasLength(1));
    expect(store.forDay(today.add(const Duration(days: 1))), isEmpty);
  });
  test(
    'pet deletion removes dependent schedules and records, preserving history',
    () async {
      store.records.add({'id': 'r', 'petId': 'p'});
      await store.complete(store.tasks.first, today);
      await store.removePet('p');
      expect(store.pets, isEmpty);
      expect(store.tasks, isEmpty);
      expect(store.records, isEmpty);
      expect(store.history.single['pet'], 'Milo');
    },
  );
}
