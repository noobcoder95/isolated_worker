import 'dart:async' show Completer, StreamController, StreamSubscription;
import 'dart:collection' show LinkedHashMap;
import 'dart:js_interop';
import 'package:isolated_worker/src/isolated_worker_web.dart';
import 'package:web/web.dart' as web;

const int _kMaxCallbackMessageId = 1000;

class JsIsolatedWorkerImpl implements JsIsolatedWorker {
  factory JsIsolatedWorkerImpl() => _instance;

  JsIsolatedWorkerImpl._() {
    _init();
  }

  static final JsIsolatedWorkerImpl _instance = JsIsolatedWorkerImpl._();

  final LinkedHashMap<List<dynamic>, dynamic> _callbackObjects =
  LinkedHashMap<List<dynamic>, dynamic>(
    equals: (List<dynamic> a, List<dynamic> b) => a[0] == b[0],
    hashCode: (List<dynamic> callbackObject) => callbackObject[0].hashCode,
  );

  final Completer<web.Worker?> _workerCompleter = Completer<web.Worker?>();

  Future<web.Worker?> get _worker => _workerCompleter.future;

  StreamSubscription<web.MessageEvent>? _workerMessages;
  late dynamic _eventListener;

  int _callbackMessageId = 0;

  void _init() {
    try {
      final web.Worker worker = web.Worker('worker.js'.toJS);
      _workerCompleter.complete(worker);

      final StreamController<web.MessageEvent> messageStreamController = StreamController.broadcast();
      _eventListener = (web.Event event) {
        if (!messageStreamController.isClosed) {
          messageStreamController.add(event as web.MessageEvent);
        }
      };
      worker.addEventListener('message', _eventListener as web.EventListener);
      _workerMessages = messageStreamController.stream.listen(_workerMessageReceiver);
    } catch (e) {
      _workerCompleter.complete(null);
    }
  }

  void _resetCurrentCallbackMessageIdIfReachedMax() {
    if (_callbackMessageId == _kMaxCallbackMessageId) {
      _callbackMessageId = 0;
    }
  }

  void _workerMessageReceiver(web.MessageEvent message) {
    final List messageData = [];
    if(message.data != null) {
      final jsArray = message.data! as JSArray;
      for (var i = 0; i < jsArray.length; i++) {
        messageData.add(jsArray[i]);
      }
    }
    final Completer<dynamic> callbackCompleter =
    _callbackObjects.remove(messageData) as Completer<dynamic>;
    final String type = messageData[2] as String;
    final dynamic resultOrError = messageData[3];
    if (type == 'result') {
      callbackCompleter.complete(resultOrError);
    } else if (type == 'error') {
      callbackCompleter.completeError(resultOrError as Object);
    }
  }

  @override
  Future<bool> importScripts(List<String> scripts) async {
    assert(scripts.isNotEmpty);
    final web.Worker? worker = await _worker;
    if (worker != null) {
      worker.postMessage(['\$init_scripts', ...scripts].jsify());
      return true;
    }
    return false;
  }

  @override
  Future<dynamic> run({
    required dynamic functionName,
    required dynamic arguments,
    Future<dynamic> Function()? fallback,
  }) async {
    assert(functionName != null);
    final web.Worker? worker = await _worker;
    if (worker == null) {
      return fallback?.call();
    }
    _resetCurrentCallbackMessageIdIfReachedMax();
    final Completer<dynamic> callbackCompleter = Completer<dynamic>();
    final List<dynamic> callbackMessage = <dynamic>[
      _callbackMessageId++,
      functionName,
      arguments,
    ];

    _callbackObjects[callbackMessage] = callbackCompleter;
    worker.postMessage(callbackMessage.jsify());
    return callbackCompleter.future;
  }

  @override
  Future<void> close() async {
    final web.Worker? worker = await _worker;
    if (worker != null) {
      worker.removeEventListener('message', _eventListener as web.EventListener);
      _workerMessages?.cancel();
      worker.terminate();
    }
  }
}
