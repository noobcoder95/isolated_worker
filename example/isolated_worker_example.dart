import 'package:isolated_worker/isolated_worker.dart';

void tryPrint(void _) {
  print('Hello from IsolatedWorker');
}

void main() {
  IsolatedWorker.create().run(tryPrint, null).then((_) => IsolatedWorker.create().close());
}
