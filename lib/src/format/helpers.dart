import 'package:archive/archive.dart' as archive;

import '../archive.dart';
import '../format.dart';
import '../range.dart';

Archive megArchiveFromArchive(
  archive.Archive src, {
  required ArchiveFormat format,
}) {
  bool isSeekable = format is SeekableArchiveFormat;
  final ranges = <String, Range>{};

  switch (format.contentType) {
    case "application/zip":
      isSeekable = true;
      final zipDir = archive.ZipDirectory()
        ..read(
          archive.InputMemoryStream(archive.ZipEncoder().encodeBytes(src)),
        );

      for (final header in zipDir.fileHeaders) {
        ranges[header.filename] = (
          header.localHeaderOffset,
          header.localHeaderOffset + header.compressedSize,
        );
      }
    default:
      // Other formats can be handled here
      break;
  }

  final files = src.files.map((f) {
    final compressionFormat = switch (f.compression) {
      archive.CompressionType.none => ArchiveCompressionType.none,
      archive.CompressionType.deflate => ArchiveCompressionType.deflate,
      archive.CompressionType.bzip2 => ArchiveCompressionType.bzip2,
      _ => throw UnimplementedError(
        "Compression type ${f.compression} not supported",
      ),
    };
    var archiveKind = ArchiveEntryKind.file;
    if (f.isDirectory) {
      archiveKind = ArchiveEntryKind.directory;
    } else if (f.isSymbolicLink) {
      archiveKind = ArchiveEntryKind.symbolicLink;
      return ArchiveEntryLink(
        path: f.name,
        size: f.size,
        modified: f.lastModDateTime,
        mode: f.mode,
        kind: ArchiveEntryKind.symbolicLink,
        link: f.symbolicLink!,
        metadata: isSeekable
            ? ArchiveMetadata.seekable(
                compressionFormat: compressionFormat,
                offset: ranges[f.name]!.$1,
                length: ranges[f.name]!.$2 - ranges[f.name]!.$1,
                uncompressedSize: f.size,
                crc: f.crc32?.toRadixString(16).padLeft(8, '0'),
              )
            : ArchiveMetadata(
                compressionFormat: compressionFormat,
                uncompressedSize: f.size,
                crc: f.crc32?.toRadixString(16).padLeft(8, '0'),
              ),
      );
    }

    return ArchiveEntry(
      path: f.name,
      size: f.size,
      modified: f.lastModDateTime,
      mode: f.mode,
      kind: archiveKind,
      content: f.content,
      metadata: isSeekable
          ? ArchiveMetadata.seekable(
              compressionFormat: compressionFormat,
              offset: ranges[f.name]!.$1,
              length: ranges[f.name]!.$2 - ranges[f.name]!.$1,
              uncompressedSize: f.size,
              crc: f.crc32?.toRadixString(16).padLeft(8, '0'),
            )
          : ArchiveMetadata(
              compressionFormat: compressionFormat,
              uncompressedSize: f.size,
              crc: f.crc32?.toRadixString(16).padLeft(8, '0'),
            ),
    );
  }).toList();

  return format is SeekableArchiveFormat
      ? SeekableArchive(files.cast(), ArchiveIndex(), format: format)
      : Archive(files, comment: src.comment, format: format);
}
