import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/main.dart';
import 'package:petpal/store.dart';

class MemoryStore extends PetPalStore {
  @override
  Future<void> save() async {
    notifyListeners();
  }
}

void main() {
  testWidgets('first-run flow creates a pet and opens the care dashboard', (
    tester,
  ) async {
    final store = MemoryStore();
    await tester.pumpWidget(PetPalApp(store: store));
    await tester.tap(find.text('Add your first pet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Luna');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.pets.single['name'], 'Luna');
    expect(find.text('Plan a task'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('sample data and household navigation work on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStore();
    await store.demo();
    await tester.pumpWidget(PetPalApp(store: store));
    expect(find.text('0 of 4 tasks done'), findsOneWidget);
    await tester.tap(find.text('Household'));
    await tester.pumpAndSettle();
    expect(find.text('Your household'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
