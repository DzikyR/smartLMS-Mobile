import 'package:flutter_test/flutter_test.dart';
import 'package:smartlms/core/time/server_clock.dart';

class FakeMono implements MonotonicSource {
  int value = 5000;
  @override
  Future<int> nowMs() async => value;
}

void main() {
  test('waktu = jam server + selisih jam monotonic (jam HP diabaikan)', () async {
    final mono = FakeMono();
    final clock = ServerClock(mono);
    expect(clock.synced, isFalse);
    await clock.sync(1_000_000, rttMs: 200); // separuh RTT dianggap perjalanan pulang
    expect(clock.nowMs(), 1_000_100);
    mono.value += 30_000;
    await clock.tick();
    expect(clock.nowMs(), 1_030_100);
  });

  test('sisa waktu; tanpa batas → null; lewat → nol', () async {
    final mono = FakeMono();
    final clock = ServerClock(mono);
    await clock.sync(10_000);
    expect(clock.remaining(70_000), const Duration(minutes: 1));
    expect(clock.remaining(null), isNull);
    mono.value += 120_000;
    await clock.tick();
    expect(clock.remaining(70_000), Duration.zero);
  });
}
