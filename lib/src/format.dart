import 'dart:convert';
import 'dart:typed_data';

import 'archive.dart';
import 'range.dart';

abstract class Format {
  /// The file extension for this archive format
  String get extension;

  /// The content type for the archive format
  String get contentType;
}

abstract class ArchiveFormat extends Converter<Uint8List, Archive>
    implements Format {
  /// The magic bytes that identify this format
  ///
  /// If the format does not have magic bytes, return `null`
  List<int>? get magicBytes => null;

  /// Converts the given archive format into an [Archive]
  @override
  Archive convert(Uint8List data);

  const ArchiveFormat();
}

/// A compression format, used for converting from one format to another
abstract class CompressionFormat extends Converter<Uint8List, Uint8List>
    implements Format {
  /// The magic bytes that identify this format
  ///
  /// If the format does not have magic bytes, return `null`
  List<int>? get magicBytes => null;

  /// Converts the given data in this compression format into uncompressed data
  @override
  Uint8List convert(Uint8List data);

  /// The content encoding, if any
  String? get contentEncoding;

  const CompressionFormat();
}

/// An archive format consisting of two types: a compression layer and an archive layer
abstract class DualPartArchiveFormat<
  T extends ArchiveFormat,
  U extends CompressionFormat
>
    extends ArchiveFormat {
  /// The inner archive format
  T get archiveLayer;

  /// The compression format used before the archive layer
  U get compressionLayer;

  @override
  Archive convert(Uint8List data) {
    return archiveLayer.convert(compressionLayer.convert(data));
  }

  const DualPartArchiveFormat();
}

// TODO: Seeker method
abstract class SeekableArchiveFormat extends ArchiveFormat {
  /// Hints on where the index for a seekable archive format could be
  List<Range> indexHintRanges(int len);

  /// Parses a given index and creates an [ArchiveIndex]
  ArchiveIndex convertIndex(Uint8List data);

  @override
  SeekableArchive convert(Uint8List data);

  /// Converts a given entry in the given format into an [ArchiveEntry]
  ArchiveEntry convertEntry(
    Uint8List data, [
    ArchiveCompressionTypeBase? compressionFormat,
    Range? range,
  ]);

  const SeekableArchiveFormat();
}
