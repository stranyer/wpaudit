import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zona_cero/audio/sfx.dart';
import 'package:zona_cero/ui/widgets/chamfer_button.dart';
import 'package:zona_cero/ui/widgets/grit.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend fake;

  setUp(() {
    Sfx.resetForTest();
    fake = FakeBackend();
    Sfx.install(fake);
  });

  tearDown(Sfx.resetForTest);

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('ChamferButton suena al tocar (y no si está deshabilitado)', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(host(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChamferButton(label: 'Recuperar', onPressed: () => pressed++),
        const ChamferButton(label: 'Bloqueado'),
      ],
    )));
    await tester.tap(find.text('RECUPERAR'));
    await tester.tap(find.text('BLOQUEADO'));
    await tester.pump();
    expect(pressed, 1);
    expect(fake.plays.map((p) => p.id), [SfxId.tap]);
    expect(fake.plays.single.volume, lessThan(Sfx.master)); // tap discreto
  });

  testWidgets('GritTabs y LineTabs suenan solo al cambiar de pestaña', (tester) async {
    var grit = 0;
    var line = 0;
    await tester.pumpWidget(host(StatefulBuilder(
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 360, child: GritTabs(labels: const ['Objetos', 'Taller'], index: grit, onChanged: (i) => setState(() => grit = i))),
          LineTabs(labels: const ['Uno', 'Dos'], index: line, onChanged: (i) => setState(() => line = i)),
        ],
      ),
    )));
    await tester.tap(find.text('OBJETOS')); // ya activa
    await tester.tap(find.text('TALLER'));
    await tester.tap(find.text('DOS'));
    await tester.pump();
    expect(fake.plays.map((p) => p.id), [SfxId.tab, SfxId.tab]);
  });

  testWidgets('con el sonido apagado los widgets no llaman al motor', (tester) async {
    Sfx.enabled = false;
    await tester.pumpWidget(host(ChamferButton(label: 'Ok', onPressed: () {})));
    await tester.tap(find.text('OK'));
    expect(fake.plays, isEmpty);
  });
}
