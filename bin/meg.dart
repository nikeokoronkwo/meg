import 'dart:io';

import 'package:args/args.dart';
import 'package:meg/meg.dart';
import 'package:neat_cache/neat_cache.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

// TODO: Consider SSL
final ArgParser _argParser = ArgParser(allowTrailingOptions: true)
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help message')
  ..addOption('region', abbr: 'r', help: 'The S3 region to use')
  ..addOption('access-key', abbr: 'a', help: 'The S3 access key to use')
  ..addOption('secret-key', abbr: 's', help: 'The S3 secret key to use')
  ..addOption('bucket', abbr: 'b', help: 'The S3 bucket to use')
  ..addOption(
    'host',
    abbr: 'H',
    help:
        'The host to use for the service. You can also override this with the MEG_HOST environment variable',
  )
  ..addOption(
    'port',
    abbr: 'p',
    help:
        'The port to use for the service. You can also override this with the MEG_PORT environment variable',
    defaultsTo: Platform.environment['PORT'] ?? '8080',
  )
  ..addOption(
    'cache',
    help:
        'Type of cache to use for caching data for meg. By default, this is cached in-memory',
    allowed: CacheKind.values.map((v) => v.name),
    allowedHelp: CacheKind.values.asNameMap().map(
      (_, v) => MapEntry(v.name, '${v.description}\nFormat: ${v.name}:<value>'),
    ),
  )
  ..addFlag(
    'force-download',
    negatable: false,
    help: 'Force download of files instead of displaying them in the browser',
    defaultsTo: false,
  );

enum CacheKind {
  inMemory('in-memory', 'Caches archives and indexed are stored in-memory'),
  redis(
    'redis',
    'Caches archives and indexes as byte data in a redis instance at the given (url)',
    true,
  );

  const CacheKind(this.name, this.description, [this.associatedValue = false]);

  final String name;
  final String description;
  final bool associatedValue;
}

const String _description = '''
meg - Serve files from your S3 bucket over HTTP

Usage: meg <s3-url> [options]
''';

void main(List<String> args) async {
  final argResults = _argParser.parse(args);

  if (argResults['help'] as bool) {
    print(_description);
    print(_argParser.usage);
    return;
  }

  if (argResults.rest.isEmpty && Platform.environment['S3_URL'] == null) {
    print('Please provide an S3 URL');
    exit(1);
  }

  final s3Url = (argResults.rest.isNotEmpty
      ? argResults.rest.first
      : Platform.environment['S3_URL'])!;
  final s3Uri = Uri.tryParse(s3Url);
  if (s3Uri == null) {
    print('Invalid S3 URL: Got $s3Url');
    exit(1);
  }
  final region =
      argResults['region'] as String? ??
      Platform.environment['S3_REGION'] ??
      'us-east-1';
  final accessKey =
      argResults['access-key'] as String? ??
      Platform.environment['S3_ACCESS_KEY'];
  final secretKey =
      argResults['secret-key'] as String? ??
      Platform.environment['S3_SECRET_KEY'];
  final bucket =
      argResults['bucket'] as String? ?? Platform.environment['S3_BUCKET'];
  final host = argResults.wasParsed('host')
      ? argResults['host']
      : Platform.environment['MEG_HOST'] ?? (argResults['host'] as String?);
  final port =
      int.tryParse(
        argResults.wasParsed('port')
            ? argResults['port']
            : Platform.environment['MEG_PORT'] ?? argResults['port'] as String?,
      ) ??
      8080;

  var cacheProvider = Cache.inMemoryCacheProvider(5000);
  if (argResults['cache'] case final cacheValue?) {
    final cacheKind = CacheKind.values.firstWhere((v) {
      if (v.associatedValue) {
        final [name, value] = (cacheValue as String).split(':');
        return v.name.toLowerCase() == name.toLowerCase();
      }
      return v.name.toLowerCase() == (cacheValue as String).toLowerCase();
    });
    switch (cacheKind) {
      case CacheKind.redis:
        final [_, value] = (cacheValue as String).split(':');
        cacheProvider = Cache.redisCacheProvider(Uri.parse(value));
      default:
      // skip
    }
  }

  final handler = await megHandler(
    s3Uri,
    region: region,
    accessKey: accessKey,
    secretKey: secretKey,
    bucket: bucket,
    cacheProvider: cacheProvider,
    download: argResults['force-download'] as bool,
    logHandler: (record) {
      print(
        'LOG :: [${record.time.toIso8601String()}]: [${record.level}] ${record.message} ${record.error == null ? '' : '(err: ${record.error})'}',
      );
    },
  );

  final pipeline = const Pipeline()
      .addMiddleware(
        logRequests(
          logger: (msg, isError) {
            print('REQ ${isError ? '(err) ' : ''}:: $msg');
          },
        ),
      )
      .addHandler(handler);

  final server = await shelf_io.serve(
    pipeline,
    host ?? InternetAddress.anyIPv4.address,
    port,
  );

  print('Serving at http://${server.address.host}:${server.port}');
}
