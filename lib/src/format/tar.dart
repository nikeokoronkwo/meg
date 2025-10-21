import 'dart:typed_data';
import 'package:archive/archive.dart' as archive;

import '../archive.dart';
import '../format.dart';
import 'gzip.dart';
import 'helpers.dart';

class TarFormat extends ArchiveFormat {
  const TarFormat();

  @override
  String get contentType => "application/x-tar";

  @override
  Archive convert(Uint8List data) {
    final tarArchive = archive.TarDecoder().decodeBytes(data);
    return megArchiveFromArchive(tarArchive, format: this);
  }

  @override
  String get extension => "tar";
}

class TarGzFormat
    extends DualPartArchiveFormat<TarFormat, GzipCompressionFormat> {
  const TarGzFormat();

  @override
  TarFormat get archiveLayer => const TarFormat();

  @override
  GzipCompressionFormat get compressionLayer => const GzipCompressionFormat();

  @override
  String get contentType => "application/x-gtar";

  @override
  String get extension => "tgz";
}
