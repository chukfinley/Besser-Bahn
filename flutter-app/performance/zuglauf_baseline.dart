// ignore_for_file: avoid_print
void main() {
  const requestLatencies = <int>[
    // Real zuglauf API attempt times go here.
  ];

  const e2eLatencies = <int>[
    // Real zuglauf E2E times go here.
  ];

  if (requestLatencies.isEmpty || e2eLatencies.isEmpty) {
    print('No performance samples yet.');
    return;
  }

  final requests = [...requestLatencies]..sort();
  final e2e = [...e2eLatencies]..sort();

  int percentile(List<int> values, double p) {
    final index = ((values.length - 1) * p).round();
    return values[index];
  }

  double average(List<int> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  print('');
  print('Zuglauf API Baseline');
  print('====================');
  print('');
  print('Samples: ${requests.length}');
  print('Average: ${average(requests).toStringAsFixed(1)} ms');
  print('Median:  ${percentile(requests, 0.50)} ms');
  print('P95:     ${percentile(requests, 0.95)} ms');
  print('Min:     ${requests.first} ms');
  print('Max:     ${requests.last} ms');

  print('');
  print('Zuglauf E2E');
  print('-----------');
  print('Average: ${average(e2e).toStringAsFixed(1)} ms');
  print('Median:  ${percentile(e2e, 0.50)} ms');
  print('P95:     ${percentile(e2e, 0.95)} ms');
  print('Min:     ${e2e.first} ms');
  print('Max:     ${e2e.last} ms');
}
