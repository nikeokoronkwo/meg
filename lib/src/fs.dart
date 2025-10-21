import 'dart:convert';

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../meg.dart';

abstract class ReadOnlyFileSystem extends FileSystem {}

abstract class ReadOnlyFileSystemEntity implements FileSystemEntity {
  const ReadOnlyFileSystemEntity(this.fileSystem, this.path);

  @override
  final String path;

  @override
  final ReadOnlyFileSystem fileSystem;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) {
    throw FileSystemException(
      "Cannot delete file system entity: Read-Only File System",
      path,
    );
  }

  @override
  void deleteSync({bool recursive = false}) {
    throw FileSystemException(
      "Cannot delete file system entity: Read-Only File System",
      path,
    );
  }

  @override
  Future<FileSystemEntity> rename(String newPath) {
    throw FileSystemException(
      "Cannot rename system entity: Read-Only File System",
      path,
    );
  }

  @override
  FileSystemEntity renameSync(String newPath) {
    throw FileSystemException(
      "Cannot rename system entity: Read-Only File System",
      path,
    );
  }
}

class ArchiveFileSystem<T extends ArchiveMetadata> extends ReadOnlyFileSystem {
  final Archive<T> _archive;

  ArchiveFileSystem(this._archive) : _context = p.Context(style: p.Style.posix);

  p.Context _context;

  String get cwd => _context.current;

  ArchiveEntry<T>? getEntry(String path) =>
      _archive.firstWhereOrNull((entry) => this.path.equals(entry.path, path));
  List<ArchiveEntry<T>> getEntriesMatchingPrefix(String path) {
    return _archive.where((e) => this.path.isWithin(path, e.path)).toList();
  }

  @override
  Directory directory(path) => ArchiveDirectory(this, path);

  @override
  File file(path) => ArchiveFile(this, path);

  @override
  Link link(path) => ArchiveLink(this, path);

  @override
  Future<bool> identical(String path1, String path2) async =>
      identicalSync(path1, path2);

  @override
  bool identicalSync(String path1, String path2) {
    final entries1 = getEntriesMatchingPrefix(path1);
    final entries2 = getEntriesMatchingPrefix(path2);

    return entries1.isNotEmpty && entries1 == entries2;
  }

  @override
  bool get isWatchSupported => false;

  @override
  p.Context get path => _context;

  @override
  Future<FileStat> stat(String path) async => statSync(path);

  @override
  FileStat statSync(String path) {
    if (getEntry(path) case final singleArchiveFile?) {
      return singleArchiveFile._fileStat();
    } else {
      return getEntriesMatchingPrefix(path)._dirStat();
    }
  }

  @override
  Directory get systemTempDirectory => throw UnsupportedError(
    "Temp dirs not supported in read-only archive file systems",
  );

  @override
  Future<FileSystemEntityType> type(
    String path, {
    bool followLinks = true,
  }) async => typeSync(path, followLinks: followLinks);

  @override
  FileSystemEntityType typeSync(String path, {bool followLinks = true}) {
    if (getEntry(path) case final singleArchiveEntry?) {
      // check if symlink
      if (singleArchiveEntry is ArchiveEntryLink) {
        if (!followLinks) return FileSystemEntityType.link;

        // follow symlink
        return typeSync(
          (singleArchiveEntry as ArchiveEntryLink).link,
          followLinks: followLinks,
        );
      } else if (singleArchiveEntry.kind == ArchiveEntryKind.symbolicLink) {
        if (!followLinks) return FileSystemEntityType.link;

        // follow symlink
        final contents = utf8.decode(singleArchiveEntry.data).trimRight();
        final combinedPath = this.path.join(this.path.dirname(path), contents);

        return typeSync(combinedPath, followLinks: followLinks);
      } else {
        return switch (singleArchiveEntry.kind) {
          ArchiveEntryKind.fifo => FileSystemEntityType.pipe,
          ArchiveEntryKind.symbolicLink ||
          ArchiveEntryKind.hardLink => FileSystemEntityType.link,
          ArchiveEntryKind.socket => FileSystemEntityType.unixDomainSock,
          ArchiveEntryKind.file => FileSystemEntityType.file,
          _ => FileSystemEntityType.notFound,
        };
      }
    } else if (getEntriesMatchingPrefix(path) case final dirs
        when dirs.isNotEmpty) {
      return FileSystemEntityType.directory;
    } else {
      return FileSystemEntityType.notFound;
    }
  }

  @override
  Future<bool> isDirectory(String path) async => isDirectorySync(path);

  @override
  bool isDirectorySync(String path) {
    final filesInDir = getEntriesMatchingPrefix(path);
    if (filesInDir.isEmpty) return false;
    if (filesInDir.length == 1 &&
        this.path.equals(filesInDir.single.path, path))
      return false;

    return true;
  }

  @override
  Future<bool> isFile(String path) async => isFileSync(path);

  @override
  bool isFileSync(String path) {
    return getEntry(path) != null && getEntriesMatchingPrefix(path).length > 1;
  }

  @override
  Future<bool> isLink(String path) async => isLinkSync(path);

  @override
  bool isLinkSync(String path) {
    if (getEntry(path) case final entry?
        when entry is ArchiveEntryLink ||
            entry.kind == ArchiveEntryKind.symbolicLink)
      return true;
    return false;
  }

  @override
  Directory get currentDirectory => directory(cwd);

  @override
  set currentDirectory(path) {
    String value;
    if (path is Directory) {
      value = path.path;
    } else if (path is String) {
      value = path;
    } else
      throw ArgumentError("Invalid type for path: ${path?.runtimeType}");

    value = directory(path).resolveSymbolicLinksSync();
    // check if dir exists
    assert(isDirectorySync(value));
    value = this.path.isAbsolute(value) ? value : this.path.absolute(value);
    _context = p.Context(style: p.Style.posix, current: value);
  }
}

/// A [FileSystem] object for a seekable remote archive (i.e. a seekable archive not existing on the current file system)
///
/// This is to be used for operations on seekable archives without having the whole file in memory.
///
// TODO(https://github.com/nikeokoronkwo/meg/issues/5): Loads of overrides
class SeekableRemoteArchiveFileSystem extends ArchiveFileSystem {
  @override
  final SeekableRemoteArchive _archive;

  SeekableRemoteArchiveFileSystem(this._archive) : super(_archive);
}

abstract class ArchiveFileSystemEntity extends ReadOnlyFileSystemEntity {
  const ArchiveFileSystemEntity(this.fileSystem, this.path)
    : super(fileSystem, path);

  @override
  final String path;

  @override
  final ArchiveFileSystem fileSystem;

  @override
  String get dirname => fileSystem.path.dirname(path);

  @override
  String get basename => fileSystem.path.basename(path);

  @override
  bool get isAbsolute => fileSystem.path.isAbsolute(path);

  @override
  Uri get uri {
    return Uri.file(path, windows: false);
  }

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) {
    throw UnsupportedError("Watching not supported in read-only file system");
  }

  @override
  FileSystemEntity get absolute {
    String absPath = path;
    if (!fileSystem.path.isAbsolute(absPath)) {
      absPath = fileSystem.path.absolute(absPath);
    }
    return clone(absPath);
  }

  @override
  Future<String> resolveSymbolicLinks() async => resolveSymbolicLinksSync();

  @override
  String resolveSymbolicLinksSync() {
    if (path.isEmpty) {
      throw FileSystemException("No such file or directory", path);
    }

    // check if file is symlink
    final node = fileSystem._archive.firstWhere(
      (f) => fileSystem.path.equals(f.path, path),
    );
    if (node is ArchiveEntryLink) return node.link;
    if (node.kind != ArchiveEntryKind.symbolicLink) return path;

    // get contents
    final contents = utf8.decode(node.data).trimRight();
    final combinedPath = fileSystem.path.join(
      fileSystem.path.dirname(path),
      contents,
    );

    return fileSystem.path.normalize(combinedPath);
  }

  @override
  Future<FileStat> stat() => fileSystem.stat(path);

  @override
  FileStat statSync() => fileSystem.statSync(path);

  FileSystemEntity clone(String path);

  @override
  Directory get parent => ArchiveDirectory(fileSystem, dirname);
}

class ArchiveDirectory extends ArchiveFileSystemEntity implements Directory {
  ArchiveDirectory(super.fileSystem, super.path);

  @override
  Directory get absolute => super.absolute as Directory;

  List<ArchiveEntry> get backing {
    return fileSystem._archive.where((a) => p.isWithin(path, a.path)).toList();
  }

  @override
  Directory childDirectory(String basename) {
    return fileSystem.directory(fileSystem.path.join(path, basename));
  }

  @override
  File childFile(String basename) {
    return fileSystem.file(fileSystem.path.join(path, basename));
  }

  @override
  Link childLink(String basename) {
    return fileSystem.link(fileSystem.path.join(path, basename));
  }

  @override
  Future<Directory> create({bool recursive = false}) {
    throw FileSystemException(
      "Cannot create directory: Read-Only File System",
      path,
    );
  }

  @override
  void createSync({bool recursive = false}) {
    throw FileSystemException(
      "Cannot create directory: Read-Only File System",
      path,
    );
  }

  @override
  Future<Directory> createTemp([String? prefix]) {
    throw FileSystemException(
      "Cannot create directory: Read-Only File System",
      path,
    );
  }

  @override
  Directory createTempSync([String? prefix]) {
    throw FileSystemException(
      "Cannot create directory: Read-Only File System",
      path,
    );
  }

  @override
  Future<bool> exists() async => existsSync();

  @override
  bool existsSync() {
    return backing.isNotEmpty;
  }

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => Stream.fromIterable(
    _listSync(recursive: recursive, followLinks: followLinks),
  );

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => _listSync(recursive: recursive, followLinks: followLinks).toList();

  Iterable<FileSystemEntity> _listSync({
    bool recursive = false,
    bool followLinks = true,
  }) sync* {
    final p.PathSet dirs = p.PathSet(context: fileSystem.path);
    for (final archiveEntry in backing) {
      final archiveEntryPath = archiveEntry.path;
      if (recursive && fileSystem.path.dirname(archiveEntryPath) != path) {
        // yield as directory
        dirs.add(
          fileSystem.path.join(
            path,
            fileSystem.path.dirname(archiveEntry.path),
          ),
        );
      }
      if (followLinks && archiveEntry.kind == ArchiveEntryKind.symbolicLink) {
        var entry = archiveEntry;
        while (entry.kind == ArchiveEntryKind.symbolicLink) {
          var combinedPath;
          if (entry is ArchiveEntryLink) {
            combinedPath = fileSystem.path.join(
              fileSystem.path.dirname(path),
              entry.link,
            );
          } else {
            final contents = utf8.decode(archiveEntry.data).trimRight();
            combinedPath = fileSystem.path.join(
              fileSystem.path.dirname(path),
              contents,
            );
          }

          if (fileSystem._archive.where((a) => a.path == combinedPath) case [
            final ArchiveEntry targetEntry,
          ]) {
            entry = targetEntry;
          } else if (fileSystem._archive.where(
                (a) => fileSystem.path.isWithin(combinedPath, a.path),
              )
              case final items when items.isNotEmpty) {
            // dir
            dirs.add(
              fileSystem.path.join(
                path,
                fileSystem.path.dirname(items.first.path),
              ),
            );
            break;
          }
        }

        yield ArchiveFile(fileSystem, entry.path);
      } else {
        switch (archiveEntry.kind) {
          case ArchiveEntryKind.symbolicLink:
            yield ArchiveLink(fileSystem, archiveEntryPath);
          default:
            yield ArchiveFile(fileSystem, archiveEntryPath);
        }
      }
    }

    yield* dirs.map((d) => ArchiveDirectory(fileSystem, d!)).toList();
  }

  @override
  Future<Directory> rename(String newPath) {
    throw FileSystemException("Cannot rename dir: Read-Only File System", path);
  }

  @override
  Directory renameSync(String newPath) {
    throw FileSystemException("Cannot rename dir: Read-Only File System", path);
  }

  @override
  Directory clone(String path) => ArchiveDirectory(fileSystem, path);
}

class ArchiveFile extends ArchiveFileSystemEntity implements File {
  const ArchiveFile(super.fileSystem, super.path);

  @override
  File get absolute => super.absolute as File;

  ArchiveEntry? get backingOrNull {
    return fileSystem._archive.firstWhereOrNull((a) => a.path == path);
  }

  ArchiveEntry get backing {
    return fileSystem._archive.firstWhere((a) => a.path == path);
  }

  @override
  Future<File> copy(String newPath) {
    throw FileSystemException("Cannot copy file: Read-Only File System", path);
  }

  @override
  File copySync(String newPath) {
    throw FileSystemException("Cannot copy file: Read-Only File System", path);
  }

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) {
    throw FileSystemException(
      "Cannot create file: Read-Only File System",
      path,
    );
  }

  @override
  void createSync({bool recursive = false, bool exclusive = false}) {
    throw FileSystemException(
      "Cannot create file: Read-Only File System",
      path,
    );
  }

  @override
  Future<bool> exists() async => existsSync();

  @override
  bool existsSync() {
    return backingOrNull != null;
  }

  @override
  Future<DateTime> lastAccessed() async => lastAccessedSync();

  @override
  DateTime lastAccessedSync() {
    if (backing.accessed case final accessed?) return accessed;
    throw FileSystemException("Could not get last accessed date on file", path);
  }

  @override
  Future<DateTime> lastModified() async => lastModifiedSync();

  @override
  DateTime lastModifiedSync() {
    if (backing.modified case final modified?) return modified;
    throw FileSystemException("Could not get last accessed date on file", path);
  }

  @override
  Future<int> length() async => lengthSync();

  @override
  int lengthSync() {
    return backing.size;
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      openSync(mode: mode);

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    try {
      return backing.streamedData;
    } catch (e) {
      return Stream.error(e);
    }
  }

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    assert(
      mode == FileMode.read,
      "Cannot write or append to file: Read-Only File System",
    );

    // TODO: implement openSync
    throw UnimplementedError();
  }

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    throw FileSystemException(
      "Cannot set metadata on file: Read-Only File System",
      path,
    );
  }

  @override
  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  @override
  Uint8List readAsBytesSync() {
    return backing.data;
  }

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      readAsLinesSync(encoding: encoding);

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) {
    final str = readAsStringSync(encoding: encoding);

    if (str.isEmpty) return [];

    return const LineSplitter().convert(str);
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    try {
      return encoding.decode(readAsBytesSync());
    } on FormatException catch (err) {
      throw FileSystemException(err.message, path);
    }
  }

  @override
  Future setLastAccessed(DateTime time) {
    throw FileSystemException(
      "Cannot set metadata on file: Read-Only File System",
      path,
    );
  }

  @override
  void setLastAccessedSync(DateTime time) {
    throw FileSystemException(
      "Cannot set metadata on file: Read-Only File System",
      path,
    );
  }

  @override
  Future setLastModified(DateTime time) {
    throw FileSystemException(
      "Cannot set metadata on file: Read-Only File System",
      path,
    );
  }

  @override
  void setLastModifiedSync(DateTime time) {
    throw FileSystemException(
      "Cannot set metadata on file: Read-Only File System",
      path,
    );
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    throw FileSystemException(
      "Cannot write to file: Read-Only File System",
      path,
    );
  }

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    throw FileSystemException(
      "Cannot write to file: Read-Only File System",
      path,
    );
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    throw FileSystemException(
      "Cannot write to file: Read-Only File System",
      path,
    );
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    throw FileSystemException(
      "Cannot write to file: Read-Only File System",
      path,
    );
  }

  @override
  Future<File> rename(String newPath) async => renameSync(newPath);

  @override
  File renameSync(String newPath) {
    throw FileSystemException(
      "Cannot rename file: Read-Only File System",
      path,
    );
  }

  @override
  File clone(String path) => ArchiveFile(fileSystem, path);
}

class ArchiveLink extends ArchiveFileSystemEntity implements Link {
  ArchiveLink(super.fileSystem, super.path);

  @override
  Link get absolute => super.absolute as ArchiveLink;

  ArchiveEntry? get backingOrNull {
    final entryOrNull = fileSystem._archive.firstWhereOrNull(
      (a) => a.path == path,
    );
    if (entryOrNull case final entry?
        when entry.kind == ArchiveEntryKind.symbolicLink)
      return entry;
    return null;
  }

  ArchiveEntry get backing {
    final entry = fileSystem._archive.firstWhere((a) => a.path == path);
    assert(
      entry.kind == ArchiveEntryKind.symbolicLink,
      "The given file being pointed to at $path is no a symlink",
    );
    return entry;
  }

  @override
  ArchiveLink clone(String path) => ArchiveLink(fileSystem, path);

  @override
  Future<Link> create(String target, {bool recursive = false}) {
    throw FileSystemException(
      "Cannot create link: Read-Only File System",
      path,
    );
  }

  @override
  void createSync(String target, {bool recursive = false}) {
    throw FileSystemException(
      "Cannot create link: Read-Only File System",
      path,
    );
  }

  @override
  Future<bool> exists() async => existsSync();

  @override
  bool existsSync() {
    return backingOrNull != null;
  }

  @override
  Future<String> target() async => targetSync();

  @override
  String targetSync() {
    if (backing is ArchiveEntryLink) {
      return (backing as ArchiveEntryLink).link;
    }

    final contents = utf8.decode(backing.data);
    final combined = fileSystem.path.join(
      fileSystem.path.dirname(path),
      contents,
    );
    return fileSystem.path.normalize(path);
  }

  @override
  Future<Link> update(String target) {
    throw FileSystemException(
      "Cannot update symlink: Read-Only File System",
      path,
    );
  }

  @override
  void updateSync(String target) {
    throw FileSystemException(
      "Cannot update symlink: Read-Only File System",
      path,
    );
  }

  @override
  Future<Link> rename(String newPath) async => renameSync(newPath);

  @override
  Link renameSync(String newPath) {
    throw FileSystemException("Cannot rename: Read-Only File System", path);
  }
}

class ArchiveFileStat implements FileStat {
  const ArchiveFileStat(
    this.changed,
    this.modified,
    this.accessed,
    this.type,
    this.mode,
    this.size,
  );

  @override
  final DateTime accessed;

  @override
  final DateTime changed;

  @override
  final int mode;

  @override
  String modeString() {
    final int permissions = mode & 0xFFF;
    const List<String> codes = <String>[
      '---',
      '--x',
      '-w-',
      '-wx',
      'r--',
      'r-x',
      'rw-',
      'rwx',
    ];
    final List<String> result = <String>[];
    result
      ..add(codes[(permissions >> 6) & 0x7])
      ..add(codes[(permissions >> 3) & 0x7])
      ..add(codes[permissions & 0x7]);
    return result.join();
  }

  @override
  final DateTime modified;

  @override
  final int size;

  @override
  final FileSystemEntityType type;
}

extension ArchiveToArchiveFileStat on ArchiveEntry {
  ArchiveFileStat _fileStat([bool isDir = false]) {
    return ArchiveFileStat(
      changed ?? DateTime(0),
      modified ?? DateTime(0),
      accessed ?? DateTime(0),
      isDir
          ? FileSystemEntityType.directory
          : switch (kind) {
              ArchiveEntryKind.file => FileSystemEntityType.file,
              ArchiveEntryKind.directory => FileSystemEntityType.directory,
              ArchiveEntryKind.symbolicLink ||
              ArchiveEntryKind.hardLink => FileSystemEntityType.link,
              ArchiveEntryKind.socket => FileSystemEntityType.unixDomainSock,
              ArchiveEntryKind.fifo => FileSystemEntityType.pipe,
              _ => FileSystemEntityType.notFound,
            },
      mode ?? 0,
      size,
    );
  }
}

extension ArchiveListToArchiveFileStat on List<ArchiveEntry> {
  ArchiveFileStat _dirStat() {
    if (isEmpty) {
      throw Exception("No files exist");
    } else if (length == 1) {
      return single._fileStat(false);
    } else {
      final fileStats = asMap().map((_, v) {
        return MapEntry(v, v._fileStat(false));
      });
      return ArchiveFileStat(
        DateTime.fromMillisecondsSinceEpoch(
          fileStats.values.map((v) => v.changed.millisecondsSinceEpoch).max,
        ),
        DateTime.fromMillisecondsSinceEpoch(
          fileStats.values.map((v) => v.modified.millisecondsSinceEpoch).max,
        ),
        DateTime.fromMillisecondsSinceEpoch(
          fileStats.values.map((v) => v.accessed.millisecondsSinceEpoch).max,
        ),
        FileSystemEntityType.directory,
        0x41ED,
        fileStats.keys.map((v) => v.size).fold(0, (prev, next) => prev + next),
      );
    }
  }
}
