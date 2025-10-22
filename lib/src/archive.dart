import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chunked_stream/chunked_stream.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'format.dart';
import 'range.dart';

/// An archive consisting of multiple entries (e.g. files in a tarball)
///
/// This is a base class for different types of archives, such as
/// seekable archives (e.g. zip files) and non-seekable archives (e.g. tar files)
/// The archive represents a collection of entries, each with its own metadata and data
class Archive<T extends ArchiveMetadata> extends IterableBase<ArchiveEntry<T>> {
  /// The name of the archive
  final String name;

  final List<ArchiveEntry<T>> _entries;

  final String? comment;

  /// The format of the given archive
  final ArchiveFormat format;

  const Archive(
    this._entries, {
    this.name = "",
    required this.format,
    this.comment,
  });

  @override
  Iterator<ArchiveEntry<T>> get iterator => _entries.iterator;

  ArchiveEntry<T>? operator [](String path) =>
      _entries.firstWhereOrNull((entry) => entry.path == path);
}

class SeekableArchive extends Archive<SeekableArchiveMetadata> {
  final ArchiveIndex index;

  @override
  SeekableArchiveFormat get format => super.format as SeekableArchiveFormat;

  const SeekableArchive(
    super.entries,
    this.index, {
    super.name,
    required SeekableArchiveFormat format,
    super.comment,
  }) : super(format: format);
}

/// A seekable remote archive works differently from other archives in the sense
/// that it allows for archive-related operations without (necessarily)
/// having the archive on disk.
///
/// This makes it more lightweight to work with individual files in the archive,
/// but can be time-consuming to fetch data continuously
///
/// Most common operations between a [SeekableRemoteArchive] and other [Archive] implementations involves
/// converting the [SeekableRemoteArchive] into a [SeekableArchive].
abstract class SeekableRemoteArchive
    extends IterableBase<ArchiveEntry<SeekableArchiveMetadata>>
    implements Archive<SeekableArchiveMetadata> {
  /// Gets the complete source of the remote archive as bytes
  ///
  /// It is recommended to cache this call, if you plan on calling it multiple times
  Uint8List get source;

  /// Gets the complete source of the remote archive as a stream of bytes
  ///
  /// It is recommended to cache this call, if you plan on calling it multiple times
  Stream<List<int>> get sourceStream;

  /// Gets the index of the archive as bytes
  Uint8List get index;

  /// Gets the index of the archive as a stream
  Stream<List<int>> get indexStream =>
      asChunkedStream(16, Stream.fromIterable(index));

  /// Get a range of bytes in the archive
  FutureOr<Uint8List> getRange(Range range);

  @override
  SeekableArchiveFormat get format;

  SeekableArchive toLocalArchive() => format.convert(source);

  Future<SeekableArchive> toLocalArchiveAsync() async => toLocalArchive();

  @override
  List<ArchiveEntry<SeekableArchiveMetadata>> get _entries =>
      toLocalArchive()._entries;

  @override
  Iterator<ArchiveEntry<SeekableArchiveMetadata>> get iterator =>
      _entries.iterator;
}

/// An archive index is used for indexing a given archive,
/// which at its bare is a map of paths to metadata
class ArchiveIndex extends MapBase<String, SeekableArchiveMetadata> {
  final String? comment;

  final Map<String, SeekableArchiveMetadata> _index;

  ArchiveIndex([this._index = const {}, this.comment]);

  @override
  SeekableArchiveMetadata? operator [](Object? key) => _index[key];

  @override
  void operator []=(String key, SeekableArchiveMetadata value) {
    _index[key] = value;
  }

  @override
  void clear() => _index.clear();

  @override
  Iterable<String> get keys => _index.keys;

  @override
  SeekableArchiveMetadata? remove(Object? key) => _index.remove(key);
}

class ArchiveEntry<T extends ArchiveMetadata> {
  String path;

  String get name => p.basename(path);

  int size;

  /// The last time the archive entry was modified, if possible
  DateTime? modified;

  /// The last time the archive entry was accessed, if possible
  DateTime? accessed;

  /// The last time the archive entry was changed (i.e either modified, or metadata modified)
  ///
  /// At this point, this is equal to [modified]
  DateTime? get changed => modified;

  /// The time the given file was created
  DateTime? created;

  int? mode;

  ArchiveEntryKind kind;

  T metadata;

  Uint8List data;

  Stream<List<int>> get streamedData =>
      asChunkedStream(16, Stream.fromIterable(data));

  ArchiveEntry({
    required this.path,
    required this.size,
    required this.kind,
    Uint8List? content,
    this.modified,
    this.accessed,
    this.created,
    this.mode,
    required this.metadata,
  }) : data = content ?? Uint8List.fromList([]);
}

class ArchiveEntryLink<T extends ArchiveMetadata> extends ArchiveEntry<T> {
  String link;

  Encoding encoding;

  @override
  Uint8List get data => Uint8List.fromList(encoding.encode(link));

  ArchiveEntryLink({
    required super.path,
    required super.size,
    required super.kind,
    required this.link,
    super.modified,
    super.accessed,
    super.created,
    super.mode,
    required super.metadata,
    Encoding? encoding,
  }) : encoding = encoding ?? utf8;
}

enum ArchiveEntryKind {
  file,
  directory,
  symbolicLink,
  hardLink,
  fifo,
  characterDevice,
  blockDevice,
  socket,
}

/// Metadata about a given archive
class ArchiveMetadata {
  int? uncompressedSize;

  /// The CRC or checksum of the archive
  String? crc;

  ArchiveCompressionTypeBase compressionFormat;

  ArchiveMetadata({
    required this.compressionFormat,
    this.uncompressedSize,
    this.crc,
  });

  factory ArchiveMetadata.empty() =>
      ArchiveMetadata(compressionFormat: ArchiveCompressionType.none);
  factory ArchiveMetadata.seekable({
    required ArchiveCompressionTypeBase compressionFormat,
    int? uncompressedSize,
    String? crc,
    required int offset,
    required int length,
  }) = SeekableArchiveMetadata;
}

class SeekableArchiveMetadata extends ArchiveMetadata {
  final int offset;

  final int length;

  Range get range => (offset, offset + length - 1);

  SeekableArchiveMetadata({
    required this.offset,
    required this.length,
    required super.compressionFormat,
    super.uncompressedSize,
    super.crc,
  });
}

/// Archive compression formats
abstract class ArchiveCompressionTypeBase {}

enum ArchiveCompressionType implements ArchiveCompressionTypeBase {
  none,
  gzip,
  bzip2,
  xz,
  zstd,
  lzma,
  lz4,
  snappy,
  lzip,
  lzop,
  compress,
  deflate,
  brotli,
}
