import 'dart:typed_data';

import 'package:archive/archive.dart' as ar;

import '../archive.dart';
import '../format.dart';
import '../range.dart';
import 'helpers.dart';

class ZipFormat extends SeekableArchiveFormat {
  const ZipFormat();

  @override
  String get contentType => "application/zip";

  @override
  SeekableArchive convert(Uint8List data) {
    return megArchiveFromArchive(
          ar.ZipDecoder().decodeBytes(data),
          format: this,
        )
        as SeekableArchive;
  }

  @override
  ArchiveEntry convertEntry(
    Uint8List data, [
    ArchiveCompressionTypeBase? compressionFormat,
    Range? range,
  ]) {
    final archiveFile = ar.ZipFile(null)..read(ar.InputMemoryStream(data));

    return zipEntryFromFile(
      archiveFile,
      compressionFormat: compressionFormat,
      range: range ?? (0, data.length),
    );
  }

  @override
  ArchiveIndex convertIndex(Uint8List data) {
    final zipDir = ar.ZipDirectory()..read(ar.InputMemoryStream(data));
    final entries = <ArchiveEntry<SeekableArchiveMetadata>>[];
    for (final header in zipDir.fileHeaders) {
      final file = header.file;
      if (file != null) {
        entries.add(
          zipEntryFromFile(
            file,
            range: (
              header.localHeaderOffset,
              header.localHeaderOffset + header.compressedSize,
            ),
          ),
        );
      }
    }
    return ArchiveIndex(
      entries.asMap().map((_, v) => MapEntry(v.name, v.metadata)),
    );
  }

  @override
  String get extension => "zip";

  @override
  List<Range> indexHintRanges(int len) {
    return [(len - 65536, len)];
  }
}

// TODO: The info provided by package:archive is not ideally enough (especially for file-system accurate rep)
// In the future, might implement this myself
ArchiveEntry<SeekableArchiveMetadata> zipEntryFromFile(
  ar.ZipFile f, {
  ArchiveCompressionTypeBase? compressionFormat,
  required Range range,
}) {
  const archiveKind = ArchiveEntryKind.file;
  compressionFormat ??= switch (f.compressionMethod) {
    ar.CompressionType.none => ArchiveCompressionType.none,
    ar.CompressionType.deflate => ArchiveCompressionType.deflate,
    ar.CompressionType.bzip2 => ArchiveCompressionType.bzip2,
  };
  return ArchiveEntry<SeekableArchiveMetadata>(
    path: f.filename,
    size: f.compressedSize,
    modified: _dateFromDos(f.lastModFileDate, f.lastModFileTime),
    kind: archiveKind,
    content: f.getRawContent(),
    metadata: SeekableArchiveMetadata(
      compressionFormat: compressionFormat,
      offset: f.header?.localHeaderOffset ?? range.$1,
      length: f.compressedSize,
      uncompressedSize: f.uncompressedSize,
      crc: f.crc32.toRadixString(16).padLeft(8, '0'),
    ),
  );
}

DateTime _dateFromDos(int dosDate, int dosTime) {
  final year = ((dosDate >> 9) & 0x7F) + 1980;
  final month = (dosDate >> 5) & 0x0F;
  final day = dosDate & 0x1F;
  final hour = (dosTime >> 11) & 0x1F;
  final minute = (dosTime >> 5) & 0x3F;
  final second = (dosTime & 0x1F) * 2;
  return DateTime(year, month, day, hour, minute, second);
}
