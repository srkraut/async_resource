library async_resource;

import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:meta/meta.dart';

export 'src/http_network_resource.dart';

/// [contents] will either be a [String] or [List<int>], depending on whether
/// the underlying resource is binary or string based.
typedef T Parser<T>(dynamic contents);

/// An [AsyncResource] represents data from the network or disk such as a native
/// I/O File, browser service-worker cache, or browser local storage.
abstract class AsyncResource<T> {
  AsyncResource({@required this.location});

  /// The location (a path or url) of the resource.
  final String location;

  /// Gets the most readily available data or refreshes it if [forceReload] is
  /// `true`.
  Future<T> get({bool forceReload: false});

  /// Fetch the raw contents from the underlying platform.
  ///
  /// Returns a [String] or [List<int>], depending on whether the underlying
  /// resource is binary or string based.
  Future<dynamic> fetchContents();
}

/// A local resources such as a native file or browser cache.
abstract class LocalResource<T> extends AsyncResource<T> {
  LocalResource({@required String path, this.parser}) : super(location: path);

  /// Synchronously get the most recently loaded data.
  T get data => _data;
  T _data;

  final Parser<T> parser;

  @override
  Future<T> get({bool forceReload: false}) async {
    if (_data == null || forceReload) {
      _update(await fetchContents());
    }
    return _data;
  }

  /// [contents] is a [String] or [List<int>], depending on whether the
  /// underlying resource is binary or string based.
  ///
  /// The default implementation simply returns [contents]. Implementations
  /// should override this to return [T].
  T parseContents(dynamic contents) =>
      parser == null ? contents : parser(contents);

  /// For internal parsing before calling [parseContents].
  dynamic preParseContents(dynamic contents) => contents;

  /// This resource's path on the system.
  String get path => location;

  /// The [basename()] of the [path].
  String get basename => p.basename(path);

  Future<bool> get exists;

  /// Returns `null` if [exists] is `false`.
  Future<DateTime> get lastModified;

  /// Remove this resource from disk and sets [data] to `null`.
  ///
  /// Implementations should call super *after* performing the delete.
  @mustCallSuper
  Future<void> delete() async => _data = null;

  /// Persist the contents to disk.
  ///
  /// Implementations should call super *after* performing the write.
  @mustCallSuper
  Future<T> write(dynamic contents) async => _update(contents);

  T _update(contents) => _data = parseContents(preParseContents(contents));
}

/// Network resources are fetched from the network and will cache a local copy.
///
/// The default [strategy] is to use [CacheStrategy.networkFirst] and fallback
/// on cache when the network is unavailable.
abstract class NetworkResource<T> extends AsyncResource<T> {
  NetworkResource(
      {@required String url,
      @required this.cache,
      this.maxAge,
      CacheStrategy strategy})
      : strategy = strategy ?? CacheStrategy.networkFirst,
        super(location: url);

  /// The local copy of the data fetched from [url].
  final LocalResource<T> cache;

  /// Determines when the [cache] copy has expired and should be refetched.
  final Duration maxAge;

  final CacheStrategy strategy;

  /// The location of the data to fetch and cache.
  String get url => location;

  /// Returns `true` if [cache] does not exist, `false` if it exists but
  /// [maxAge] is null; otherwise compares the [cache]'s age to [maxAge].
  Future<bool> get isExpired async =>
      hasExpired(await cache.lastModified, maxAge);

  /// Retrieve the data from RAM if possible, otherwise fallback to cache or
  /// network, depending on the [strategy].
  ///
  /// If [forceReload] is `true` then this will fetch from the network, using
  /// the cache as a fallback unless [allowCacheFallback] is `false`.
  ///
  /// [allowCacheFallback] only affects network requests. The cache can still
  /// be used if it is not expired and [forceReload] is `false`.
  @override
  Future<T> get(
      {bool forceReload: false,
      bool allowCacheFallback: true,
      bool skipCacheWrite: false}) async {
    if (cache.data != null && !forceReload) {
      print('${cache.basename}: Using previously loaded value.');
      return cache.data;
    } else if (forceReload ||
        strategy == CacheStrategy.networkFirst ||
        await isExpired) {
      print('${cache.basename}: Fetching from $url');
      final contents = await fetchContents();
      if (contents != null) {
        print('$url Fetched.');
        if (!skipCacheWrite) {
          print('Updating cache...');
          return cache.write(contents);
        } else {
          return cache._update(contents);
        }
      } else {
        if (allowCacheFallback) {
          print('$url Using a cached copy if available.');
          return cache.get();
        } else {
          print('Not attempting to find in cache.');
          return null;
        }
      }
    } else {
      print('Loading cached copy of ${cache.basename}');
      return cache.get();
    }
  }
}

enum CacheStrategy { networkFirst, cacheFirst }

bool hasExpired(DateTime date, Duration maxAge) {
  return date == null
      ? true
      : (maxAge == null ? false : new DateTime.now().difference(date) > maxAge);
}
