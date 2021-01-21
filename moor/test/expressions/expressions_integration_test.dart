@TestOn('vm')
import 'package:moor/ffi.dart';
import 'package:moor/moor.dart';
import 'package:test/test.dart';

import '../data/tables/todos.dart';

void main() {
  late TodoDb db;

  setUp(() async {
    db = TodoDb(VmDatabase.memory());

    // we selectOnly from users for the lack of a better option. Insert one
    // row so that getSingle works
    await db.into(db.users).insert(
        UsersCompanion.insert(name: 'User name', profilePicture: Uint8List(0)));
  });

  tearDown(() => db.close());

  Future<T> eval<T>(Expression<T> expr) {
    final query = db.selectOnly(db.users)..addColumns([expr]);
    return query.getSingle().then((row) => row.read(expr));
  }

  test('plus and minus on DateTimes', () async {
    const nowExpr = currentDateAndTime;
    final tomorrow = nowExpr + const Duration(days: 1);
    final nowStamp = nowExpr.secondsSinceEpoch;
    final tomorrowStamp = tomorrow.secondsSinceEpoch;

    final row = await (db.selectOnly(db.users)
          ..addColumns([nowStamp, tomorrowStamp]))
        .getSingle();

    expect(row.read(tomorrowStamp) - row.read(nowStamp),
        const Duration(days: 1).inSeconds);
  });

  test('datetime.date format', () {
    final expr = Variable.withDateTime(DateTime(2020, 09, 04, 8, 55));
    final asDate = expr.date;

    expect(eval(asDate), completion('2020-09-04'));
  });

  group('text', () {
    test('contains', () {
      const stringLiteral = Constant('Some sql string literal');
      final containsSql = stringLiteral.contains('sql');

      expect(eval(containsSql), completion(isTrue));
    });

    test('trim()', () {
      const literal = Constant('  hello world    ');
      expect(eval(literal.trim()), completion('hello world'));
    });

    test('trimLeft()', () {
      const literal = Constant('  hello world    ');
      expect(eval(literal.trimLeft()), completion('hello world    '));
    });

    test('trimRight()', () {
      const literal = Constant('  hello world    ');
      expect(eval(literal.trimRight()), completion('  hello world'));
    });
  });

  test('coalesce', () async {
    final expr = coalesce<int>([const Constant(null), const Constant(3)]);

    expect(eval(expr), completion(3));
  });
}
