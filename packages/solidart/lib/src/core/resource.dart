import 'dart:async';

import 'package:meta/meta.dart';
import 'package:solidart/src/core/signal.dart';
import 'package:solidart/src/core/signal_base.dart';

/// {@macro resource}
Resource<ResultType> createResource<ResultType>({
  Future<ResultType> Function()? fetcher,
  Stream<ResultType>? stream,
  SignalBase<dynamic>? source,
}) {
  return Resource<ResultType>(
    fetcher: fetcher,
    source: source,
    stream: stream,
  );
}

/// {@template resource}
/// `Resources` are special `Signal`s designed specifically to handle Async
/// loading. Their purpose is wrap async values in a way that makes them easy
/// to interact with handling the common states of a future __data__, __error__
/// and __loading__.
///
/// Resources can be driven by a `source` signal that provides the query to an
/// async data `fetcher` function that returns a `Future`.
///
/// The contents of the `fetcher` function can be anything. You can hit typical
/// REST endpoints or GraphQL or anything that generates a future. Resources
/// are not opinionated on the means of loading the data, only that they are
/// driven by futures.
///
/// Let's create a Resource:
///
/// ```dart
/// // Using http as a client
/// import 'package:http/http.dart' as http;
///
/// // The source
/// final userId = createSignal(1);
///
/// // The fetcher
/// Future<String> fetchUser() async {
///     final response = await http.get(
///       Uri.parse('https://swapi.dev/api/people/${userId.value}/'),
///     );
///     return response.body;
/// }
///
/// // The resource (source is optional)
/// final user = createResource(fetcher: fetchUser, source: userId);
/// ```
///
/// A Resource can also be driven from a [stream] instead of a Future.
/// In this case you just need to pass the `stream` field to the
/// `createResource` method.
/// The [source] field is ignored for the [stream] and used only for a
/// [fetcher].
///
/// If you are using the `flutter_solidart` library, check
/// `ResourceBuilder` to learn how to react to the state of the resource in the
/// UI.
///
/// The resource has a value named `ResourceValue`, that provides many useful
/// convenience methods to correctly handle the state of the resource.
///
/// The `on` method forces you to handle all the states of a Resource
/// (_ready_, _error_ and _loading_).
/// The are also other convenience methods to handle only specific states:
/// - `on` forces you to handle all the states of a Resource
/// - `maybeOn` lets you decide which states to handle and provide an `orElse`
/// action for unhandled states
/// - `map` equal to `on` but gives access to the `ResourceValue` data class
/// - `maybeMap` equal to `maybeMap` but gives access to the `ResourceValue`
/// data class
/// - `isReady` indicates if the `Resource` is in the ready state
/// - `isLoading` indicates if the `Resource` is in the loading state
/// - `hasError` indicates if the `Resource` is in the error state
/// - `asReady` upcast `ResourceValue` into a `ResourceReady`, or return null if the `ResourceValue` is in loading/error state
/// - `asError` upcast `ResourceValue` into a `ResourceError`, or return null if the `ResourceValue` is in loading/ready state
/// - `value` attempts to synchronously get the value of `ResourceReady`
/// - `error` attempts to synchronously get the error of `ResourceError`
///
/// A `Resource` provides the `resolve` and `refetch` methods.
///
/// The `resolve` method must be called only once for the lifecycle of the
/// resource.
/// If runs the `fetcher` for the first time and then it listen to the
/// [source], if provided.
/// If you're passing a [stream] it subscribes to it.
///
/// The `refetch` method forces an update and calls the `fetcher` function
/// again.
/// {@endtemplate}
class Resource<ResultType> extends Signal<ResourceValue<ResultType>> {
  /// {@macro resource}
  Resource({
    this.fetcher,
    this.stream,
    this.source,
    super.options,
  })  : assert(
          (fetcher != null) ^ (stream != null),
          'Provide a fetcher or a stream',
        ),
        super(ResourceValue<ResultType>.unresolved());

  /// Reactive signal values passed to the fetcher, optional
  /// Has no effect on a [stream].
  final SignalBase<dynamic>? source;

  /// The asynchrounous function used to retrieve data.
  final Future<ResultType> Function()? fetcher;

  /// The stream used to retrieve data.
  final Stream<ResultType>? stream;
  StreamSubscription<ResultType>? _streamSubscription;

  /// Resolves the [Resource].
  ///
  /// If you provided a [fetcher], it run the async call and then it
  /// will subscribe to the [source], if provided.
  /// Otherwise it starts listening to the [stream].
  ///
  /// This method must be called once during the life cycle of the resource.
  Future<void> resolve() async {
    assert(
      value is ResourceUnresolved<ResultType>,
      """The resource has been already resolved, you can't resolve it more than once. Use `refetch()` instead if you want to refresh the value.""",
    );
    if (fetcher != null) {
      // start fetching
      await _fetch();
      // react to the [source], if provided.
      if (source != null) {
        source!.addListener(refetch);
        source!.onDispose(() => source!.removeListener(refetch));
      }
    }
    // React the the [stream], if provided
    if (stream != null) {
      _listenToStream();
    }
  }

  /// Runs the [fetcher] for the first time.
  ///
  /// You may not use this method directly on Flutter apps because the
  /// operation is already performed by `ResourceBuilder`.
  Future<void> _fetch() async {
    assert(fetcher != null, 'You are trying to fetch, but fetcher is null');
    assert(
      value is ResourceUnresolved<ResultType>,
      "Cannot fetch a resource that is already resolved, use 'refetch' instead",
    );
    try {
      value = ResourceValue<ResultType>.loading();
      final result = await fetcher!();
      value = ResourceValue<ResultType>.ready(result);
    } catch (e, s) {
      value = ResourceValue<ResultType>.error(e, stackTrace: s);
    }
  }

  /// Starts listening to the [stream] provided.
  void _listenToStream() {
    value = ResourceValue<ResultType>.loading();
    _streamSubscription = stream!.listen(
      (data) {
        value = ResourceValue<ResultType>.ready(data);
      },
      onError: (Object error, StackTrace stackTrace) {
        value = ResourceValue<ResultType>.error(error, stackTrace: stackTrace);
      },
    );
  }

  /// Force a refresh of the [fetcher].
  Future<void> refetch() async {
    assert(fetcher != null, 'You are trying to refetch, but fetcher is null');
    try {
      if (value is ResourceReady<ResultType>) {
        update(
          (value) =>
              (value as ResourceReady<ResultType>).copyWith(refreshing: true),
        );
      } else {
        value = ResourceValue<ResultType>.loading();
      }
      final result = await fetcher!();
      value = ResourceValue<ResultType>.ready(result);
    } catch (e, s) {
      value = ResourceValue<ResultType>.error(e, stackTrace: s);
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  String toString() =>
      '''Resource<$ResultType>(value: $value, previousValue: $previousValue, options; $options)''';
}

/// Manages all the different states of a [Resource]:
/// - ResourceUnresolved
/// - ResourceReady
/// - ResourceLoading
/// - ResourceError
@sealed
@immutable
abstract class ResourceValue<T> {
  /// The initial state of a [ResourceValue].
  const factory ResourceValue.unresolved() = ResourceUnresolved<T>;

  /// Creates an [ResourceValue] with a data.
  ///
  /// The data can be `null`.
  const factory ResourceValue.ready(T data) = ResourceReady<T>;

  /// Creates an [ResourceValue] in loading state.
  ///
  /// Prefer always using this constructor with the `const` keyword.
  // coverage:ignore-start
  const factory ResourceValue.loading() = ResourceLoading<T>;
  // coverage:ignore-end

  /// Creates an [ResourceValue] in error state.
  ///
  /// The parameter [error] cannot be `null`.
  // coverage:ignore-start
  const factory ResourceValue.error(Object error, {StackTrace? stackTrace}) =
      ResourceError<T>;
  // coverage:ignore-end

  /// private mapper, so that classes inheriting Resource can specify their own
  /// `map` method with different parameters.
  R map<R>({
    required R Function(ResourceReady<T> ready) ready,
    required R Function(ResourceError<T> error) error,
    required R Function(ResourceLoading<T> loading) loading,
  });
}

/// Creates an [ResourceValue] in ready state with a data.
@immutable
class ResourceReady<T> implements ResourceValue<T> {
  /// Creates an [ResourceValue] with a data.
  const ResourceReady(this.value, {this.refreshing = false});

  /// The value currently exposed.
  final T value;

  /// Indicates if the data is being refreshed, defaults to false.
  final bool refreshing;

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(ResourceReady<T> ready) ready,
    required R Function(ResourceError<T> error) error,
    required R Function(ResourceLoading<T> loading) loading,
  }) {
    return ready(this);
  }

  @override
  String toString() {
    return 'ResourceReady<$T>(value: $value, refreshing: $refreshing)';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType &&
        other is ResourceReady<T> &&
        other.value == value &&
        other.refreshing == refreshing;
  }

  @override
  int get hashCode => Object.hash(runtimeType, value, refreshing);

  /// Convenience method to update the [refreshing] value of a [Resource]
  ResourceReady<T> copyWith({
    bool? refreshing,
  }) {
    return ResourceReady(
      value,
      refreshing: refreshing ?? this.refreshing,
    );
  }
  // coverage:ignore-end
}

/// {@template resourceloading}
/// Creates an [ResourceValue] in loading state.
///
/// Prefer always using this constructor with the `const` keyword.
/// {@endtemplate}
@immutable
class ResourceLoading<T> implements ResourceValue<T> {
  /// {@macro resourceloading}
  const ResourceLoading();

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(ResourceReady<T> ready) ready,
    required R Function(ResourceError<T> error) error,
    required R Function(ResourceLoading<T> loading) loading,
  }) {
    return loading(this);
  }

  @override
  String toString() {
    return 'ResourceLoading<$T>()';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType;
  }

  @override
  int get hashCode => runtimeType.hashCode;
  // coverage:ignore-end
}

/// {@template resourceerror}
/// Creates an [ResourceValue] in error state.
///
/// The parameter [error] cannot be `null`.
/// {@endtemplate}
@immutable
class ResourceError<T> implements ResourceValue<T> {
  /// {@macro resourceerror}
  const ResourceError(
    this.error, {
    this.stackTrace,
  });

  /// The error.
  final Object error;

  /// The stackTrace of [error], optional.
  final StackTrace? stackTrace;

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(ResourceReady<T> ready) ready,
    required R Function(ResourceError<T> error) error,
    required R Function(ResourceLoading<T> loading) loading,
  }) {
    return error(this);
  }

  @override
  String toString() {
    return 'ResourceError<$T>(error: $error, stackTrace: $stackTrace)';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType &&
        other is ResourceError<T> &&
        other.error == error &&
        other.stackTrace == stackTrace;
  }

  @override
  int get hashCode => Object.hash(runtimeType, error, stackTrace);
  // coverage:ignore-end
}

/// {@template resourceunresolved}
/// Creates an [ResourceValue] in unresolved state.
/// {@endtemplate}
@immutable
class ResourceUnresolved<T> implements ResourceValue<T> {
  /// {@macro resourceunresolved}
  const ResourceUnresolved();

  // coverage:ignore-start
  @override
  R map<R>({
    required R Function(ResourceReady<T> ready) ready,
    required R Function(ResourceError<T> error) error,
    required R Function(ResourceLoading<T> loading) loading,
  }) {
    throw Exception('Cannot map an unresolved resource');
  }

  @override
  String toString() {
    return 'ResourceUnresolved<$T>()';
  }

  @override
  bool operator ==(Object other) {
    return runtimeType == other.runtimeType;
  }

  @override
  int get hashCode => runtimeType.hashCode;
  // coverage:ignore-end
}

/// Some useful extension available on any [ResourceValue].
// coverage:ignore-start
extension ResourceExtensions<T> on ResourceValue<T> {
  /// Indicates if the resource is loading.
  bool get isLoading => this is ResourceLoading<T>;

  /// Indicates if the resource has an error.
  bool get hasError => this is ResourceError<T>;

  /// Indicates if the resource is ready.
  bool get isReady => this is ResourceReady<T>;

  /// Upcast [ResourceValue] into a [ResourceReady], or return null if the
  /// [ResourceValue] is in loading/error state.
  ResourceReady<T>? get asReady {
    return map(
      ready: (r) => r,
      error: (_) => null,
      loading: (_) => null,
    );
  }

  /// Upcast [ResourceValue] into a [ResourceError], or return null if the
  /// [ResourceValue] is in ready/loading state.
  ResourceError<T>? get asError {
    return map(
      error: (e) => e,
      ready: (_) => null,
      loading: (_) => null,
    );
  }

  /// Attempts to synchronously get the value of [ResourceReady].
  ///
  /// On error, this will rethrow the error.
  /// If loading, will return `null`.
  T? get value {
    return map(
      ready: (r) => r.value,
      // ignore: only_throw_errors
      error: (r) => throw r.error,
      loading: (_) => null,
    );
  }

  /// Attempts to synchronously get the value of [ResourceReady].
  ///
  /// On error, this will rethrow the error.
  /// If loading, will return `null`.
  T? call() => value;

  /// Attempts to synchronously get the error of [ResourceError].
  ///
  /// On other states will return `null`.
  Object? get error {
    return map(
      error: (r) => r.error,
      ready: (_) => null,
      loading: (_) => null,
    );
  }

  /// Perform some actions based on the state of the [ResourceValue], or call
  /// orElse if the current state is not considered.
  R maybeMap<R>({
    required R Function() orElse,
    R Function(ResourceReady<T> ready)? ready,
    R Function(ResourceError<T> error)? error,
    R Function(ResourceLoading<T> loading)? loading,
  }) {
    return map(
      ready: (r) {
        if (ready != null) return ready(r);
        return orElse();
      },
      error: (d) {
        if (error != null) return error(d);
        return orElse();
      },
      loading: (l) {
        if (loading != null) return loading(l);
        return orElse();
      },
    );
  }

  /// Performs an action based on the state of the [ResourceValue].
  ///
  /// All cases are required.
  R on<R>({
    required R Function(T data, bool refreshing) ready,
    required R Function(Object error, StackTrace? stackTrace) error,
    required R Function() loading,
  }) {
    return map(
      ready: (r) => ready(r.value, r.refreshing),
      error: (e) => error(e.error, e.stackTrace),
      loading: (l) => loading(),
    );
  }

  /// Performs an action based on the state of the [ResourceValue], or call
  /// [orElse] if the current state is not considered.
  R maybeOn<R>({
    required R Function() orElse,
    R Function(T data, bool refreshing)? ready,
    R Function(Object error, StackTrace? stackTrace)? error,
    R Function()? loading,
  }) {
    return map(
      ready: (r) {
        if (ready != null) return ready(r.value, r.refreshing);
        return orElse();
      },
      error: (e) {
        if (error != null) return error(e.error, e.stackTrace);
        return orElse();
      },
      loading: (l) {
        if (loading != null) return loading();
        return orElse();
      },
    );
  }
}
// coverage:ignore-end
