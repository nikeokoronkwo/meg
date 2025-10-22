import 'dart:convert';
import 'dart:typed_data';

import 'package:aws_s3_api/s3-2006-03-01.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:neat_cache/cache_provider.dart';
import 'package:neat_cache/neat_cache.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'src/archive.dart';
import 'src/format.dart';
import 'src/format/tar.dart';
import 'src/format/zip.dart';
import 'src/fs.dart';
import 'src/memoizer.dart';
import 'src/utils.dart';

export 'src/archive.dart';
export 'src/format.dart';
export 'src/format/gzip.dart';
export 'src/format/tar.dart';
export 'src/range.dart';

class FileInput {
  final String? path;
  final Uint8List data;

  FileInput(this.path, this.data);
}

/// Converts an [Archive] into its own file system for accessing invidiual files and items in the archive.
///
/// For converting an archive from bytes, use [convertToFileSystem]
FileSystem archiveToFileSystem(Archive archive) {
  if (archive is SeekableRemoteArchive) {
    return SeekableRemoteArchiveFileSystem(archive);
  }
  return ArchiveFileSystem(archive);
}

/// Converts an archive in bytes into its own file system for accessing invidiual files and items in the archive.
///
/// This makes it possible to access individual files from an archive using file paths
///
/// You will need to provide a list of possible [ArchiveFormat]s that the archive could be in.
///
/// If you want to make a remote archive (i.e. a seekable archive stored elsewhere without having to download all the data),
/// then instead create a [SeekableRemoteArchive] and pass it to [archiveToFileSystem].
FileSystem convertToFileSystem(
  FileInput input, {
  List<ArchiveFormat> possibleFormats = const [],
}) {
  // get data from input
  final data = input.data;

  // check magic bytes or file name/extension
  // and get possible format
  final possibleFormat = possibleFormats.firstWhereOrNull((format) {
    if (format.magicBytes case final magicBytes?) {
      return magicBytes == data.sublist(0, magicBytes.length);
    } else if (input.path case final inputPath?) {
      return p.extension(inputPath) == format.extension ||
          inputPath.endsWith(format.extension);
    } else {
      return tryOrNull(() => format.convert(data)) != null;
    }
  });

  if (possibleFormat == null) {
    throw Exception(
      "Could not find any of the formats suitable for input data",
    );
  }

  // convert to archive
  final archive = possibleFormat.convert(data);

  // return archive file system backed by archive
  return archiveToFileSystem(archive);
}

/// Converts an archive in bytes into its own file system for accessing invidiual files and items in the archive,
/// using a specific [ArchiveFormat].
FileSystem convertToFileSystemWithFormat(
  FileInput input,
  ArchiveFormat format,
) {
  return archiveToFileSystem(format.convert(input.data));
}

void _defaultLogHandler(LogRecord record) {
  print("object");
}

/// Creates a shelf handler for converting archives in an S3 bucket into a file server.
///
/// **NOTE**: For now, this only supports objects in the top level.
///
/// By default the requests respond with text corresponding to the file content.
/// You can make responses respond with file downloads by setting [download] to `true`
///
/// The handler requires a valid S3 url, which can be in one of the following formats:
/// ```
/// https://<bucket>.s3.amazonaws.com/
/// https://s3.amazonaws.com/<bucket>
/// s3://<bucket>/
/// ```
///
/// If the S3 URL does not fit either of these formats, then you can pass the bucket name using [bucket].
///
/// Credentials are supported via [accessKey] and [secretKey], as well as [region].
///
/// By default, certain requests for S3 objects (such as metadata and non-seekable archive requests) are cached.
/// This cache is, by default, an in-memory TTL cache.
/// You can use your own cache by passing a [Uint8List]-compatible [CacheProvider] via [cacheProvider].
///
/// Supported archive formats by default are `.tar.gz` and `.zip`. You can add custom formats through the [supportedFormats] object.
/// For more information on formats, check out the [ArchiveFormat] class.
///
/// Custom logging can be supported by passing a [logHandler] to the handler. By default, logs are printed to stdout.
// TODO: Add option to cache ranged (index) requests
// TODO(https://github.com/nikeokoronkwo/meg/issues/1): Add logging
// TODO(https://github.com/nikeokoronkwo/meg/issues/5): Convert pipeline for seekable archives to follow normal archives and use the [SeekableRemoteArchiveFileSystem] format
// TODO(https://github.com/nikeokoronkwo/meg/issues/2): Support pub/sub
// TODO(https://github.com/nikeokoronkwo/meg/issues/3): Support periodic polling on cache etag
Future<Handler> megHandler(
  Uri s3Uri, {
  String region = 'us-east-1',
  String? accessKey,
  String? secretKey,
  String? bucket,
  CacheProvider<List<int>>? cacheProvider,
  bool download = false,
  List<ArchiveFormat> supportedFormats = const [],
  Function(LogRecord)? logHandler,
}) async {
  hierarchicalLoggingEnabled = true;
  logHandler ??= _defaultLogHandler;

  final logger = Logger('MEG');
  logger.level = Level.ALL;
  logger.onRecord.listen(logHandler);

  final archiveFormats = supportedFormats.isEmpty
      ? <ArchiveFormat>[const TarGzFormat(), const ZipFormat()]
      : supportedFormats;
  final mimeResolver = MimeTypeResolver();
  for (final format in archiveFormats) {
    // TODO: If already present, lets not overwrite
    if (format is DualPartArchiveFormat) {
      mimeResolver.addExtension(
        format.archiveLayer.extension,
        format.archiveLayer.contentType,
      );
      mimeResolver.addExtension(
        format.compressionLayer.extension,
        format.compressionLayer.contentType,
      );
      if (format.contentType != format.compressionLayer.contentType) {
        mimeResolver.addExtension(format.extension, format.contentType);
      }
    } else {
      mimeResolver.addExtension(format.extension, format.contentType);
    }
  }
  if ((accessKey == null && secretKey != null) ||
      (accessKey != null && secretKey == null)) {
    throw Exception(
      "You must pass both accessKey and secretKey, or none of them",
    );
  }

  String? bucketOrNull;

  // check for bucket name
  if (bucket != null) {
    bucketOrNull = bucket;
  } else if (s3Uri.scheme == 's3') {
    bucketOrNull = s3Uri.host;
  } else {
    final host = s3Uri.host;
    if (host == 's3.amazonaws.com') {
      bucketOrNull = s3Uri.pathSegments.first;
    } else if (host.contains('s3.amazonaws.com')) {
      final [b] = host.split('.');
      bucketOrNull = b;
    }
  }

  if (bucketOrNull == null) {
    throw Exception("The bucket must be provided for the given endpoint");
  }

  final String bucket0 = bucketOrNull;

  // initialise S3 endpoint
  final s3 = S3(
    region: region,
    credentials: accessKey == null && secretKey == null
        ? null
        : AwsClientCredentials(accessKey: accessKey!, secretKey: secretKey!),
    endpointUrl: s3Uri.toString(),
  );

  // TODO: Consider in memory archive with custom objects
  final mainCache = Cache(cacheProvider ?? Cache.inMemoryCacheProvider(5000));
  final archiveCache = mainCache.withPrefix('archives');
  final indexCache = mainCache.withPrefix('indexes');
  // TODO: Convert this to established, single type, or better still, use If-Not-Match requests
  final archiveHeadCacher = CacheableMap<(String, HeadObjectOutput)>(
    const Duration(minutes: 10),
  );

  return (Request request) async {
    final url = request.url;

    logger.info('Received ${request.method} request at ${request.url}');

    // if just the obj
    if (url.pathSegments.length == 1) {
      // serve object as is
      try {
        final object = await s3.getObject(bucket: bucket0, key: url.path);

        // TODO: cache object

        final data = object.body;

        logger.info('Received archive matching object ${url.path} at endpoint');
        logger.info('Responding with response for archive at ${url.path}');

        return Response.ok(data);
      } catch (e, stack) {
        logger.severe(
          'Error: Could not retrieve object at ${url.path} from endpoint',
          e,
          stack,
        );
        return Response.notFound('Could not get archive at path ${url.path}');
      }
    } else {
      final [archive, ...pathSegments] = url.pathSegments;
      final filePath = pathSegments.join('/');

      try {
        // check cache
        var archiveData = await archiveCache[archive].get();
        String? archiveNameWithExtension;
        ArchiveFormat? format;

        if (archiveData == null) {
          // HEAD
          // 1. HEAD info
          // 2. non-seekable: Archive itself
          // 3. seekable: index of archive
          // all based on etag

          // TODO(https://github.com/nikeokoronkwo/meg/issues/3): Periodic timer to HEAD and check for invalidation based on etag
          final cacheResult = await archiveHeadCacher.fetch(archive, () async {
            // list objects with archive name
            final objects = await s3.listObjectsV2(
              bucket: bucket0,
              prefix: archive,
            );

            // get archived formats
            // TODO: Pass converters for custom archive transformers
            assert((objects.keyCount ?? 0) > 0, "Archive does not exist");

            final possibleObject = objects.contents!.firstWhere(
              (o) => o.key != null,
            );

            // check archive
            return (
              possibleObject.key!,
              await s3.headObject(bucket: bucket0, key: possibleObject.key!),
            );
          });

          final (name, headResult) = cacheResult;

          // check
          final archiveType =
              headResult.contentType ?? mimeResolver.lookup(name);
          final archiveLength = headResult.contentLength!;
          final supportsRanges = headResult.acceptRanges != null;

          // find an archive format
          final archiveFormat = archiveFormats.firstWhere((f) {
            if (f is DualPartArchiveFormat) {
              return f.compressionLayer.contentType == archiveType ||
                  f.contentType == archiveType;
            } else {
              return f.contentType == archiveType;
            }
          });

          if (archiveFormat is SeekableArchiveFormat && supportsRanges) {
            // TODO(https://github.com/nikeokoronkwo/meg/issues/5): Convert to "FileSystem"
            final indexData = await indexCache[name].get(() async {
              // get index
              final indexHint = archiveFormat
                  .indexHintRanges(archiveLength)
                  .first;

              // perform range request
              final rangeData = await s3.getObject(
                bucket: bucket0,
                key: name,
                range: 'bytes=${indexHint.$1}-${indexHint.$2}',
              );

              // get data and parse archive index
              return rangeData.body!;
            }, const Duration(minutes: 30));

            final index = archiveFormat.convertIndex(
              Uint8List.fromList(indexData ?? []),
            );

            // get entry
            final entry = index[filePath];

            if (entry == null) {
              return Response.notFound(null);
            }

            // get offset
            final entryRange = entry.range;
            final compressionFormat = entry.compressionFormat;

            // RANGE for item
            final itemResponse = await s3.getObject(
              bucket: bucket0,
              key: name,
              range: 'bytes=${entryRange.$1}-${entryRange.$2}',
            );
            // stream data

            final finalArchive = archiveFormat.convertEntry(
              itemResponse.body!,
              compressionFormat,
            );
            final finalData = finalArchive.data;

            final mime =
                mimeResolver.lookup(filePath) ??
                tryOrElse(() {
                  final _ = utf8.decode(finalData);
                  return 'text/plain';
                }, 'application/octet-stream')!;

            return Response.ok(
              finalData,
              headers: {
                'Content-Type':
                    '$mime${mime != 'application/octet-stream' ? '; charset=utf-8' : ''}',
                if (download)
                  'Content-Disposition':
                      'attachment; filename="${filePath.split('/').last}"',
              },
            );
          } else {
            // GET full data and set
            final archiveGetResponse = await s3.getObject(
              bucket: bucket0,
              key: name,
            );

            // set cache
            final archiveBody = archiveGetResponse.body!;
            archiveCache[archive].set(archiveBody, const Duration(minutes: 30));

            archiveData = archiveBody;
            archiveNameWithExtension = name;
            format = archiveFormat;
          }
        } else {
          logger.fine('[CACHED] Retrieved archive body for archive $archive');
        }

        // with the archive data, convert to filesystem
        final archiveFS = (archiveNameWithExtension != null && format != null)
            ? convertToFileSystemWithFormat(
                FileInput(
                  archiveNameWithExtension,
                  Uint8List.fromList(archiveData),
                ),
                format,
              )
            : convertToFileSystem(
                FileInput(null, Uint8List.fromList(archiveData)),
                possibleFormats: archiveFormats,
              );

        // TODO: fse may not be file
        final file = archiveFS.file(filePath);
        if (!await file.exists()) {
          return Response.notFound(null);
        }

        final fileData = await file.readAsBytes();
        final mime =
            mimeResolver.lookup(filePath) ??
            tryOrElse(() {
              final _ = utf8.decode(fileData);
              return 'text/plain';
            }, 'application/octet-stream')!;
        return Response.ok(
          fileData,
          headers: {
            'Content-Type':
                '$mime${mime != 'application/octet-stream' ? '; charset=utf-8' : ''}',
            if (download)
              'Content-Disposition':
                  'attachment; filename="${filePath.split('/').last}"',
          },
        );
      } on AssertionError {
        rethrow;
      } catch (e, stack) {
        throw Exception("Error fetching archive or file: $e: $stack");
      }
    }
  };
}
