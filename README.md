# Meg

Meg is a lightweight, simple server for creating a file server from an S3-compatible endpoint. 

## Features
- Cache by default: Archive data is cached by default to reduce latency. Meg supports in-memory caching and redis caching.
- Seekable by default: Meg support seekable archives and prefers seeking ranges for archives rather than downloading the full archive for serving.
- Supports multiple archive formats: By default, meg supports tarballs and .zip archives, but can be used to support multiple formats as well.

Meg is designed to be usable standalone, as well as through a Dart API. Through the use of this API, you can:
- Use meg with other custom archive formats by implementing [`ArchiveFormat`](./lib/src/format.dart).
- Configure the kind of cache to use (other than in-memory or redis), logging, and more.


## Installing

Meg can be installed as a Dart package
```shell
dart pub global activate meg # Install meg
```

And you can start the server by running `meg <s3-url>`. This will start the file server at the 8080 port by default.

For more information on the CLI, you can check the help information

```shell
meg --help
```

## Docker

Meg can be used via docker.

Meg supports overriding its values using environment variables, or through passing arguments directly to the main command.

## API
Meg has a Dart API to use, as well as a shelf handler for easy integration with [`package:shelf`](https://pub.dev/packages/shelf).

The shelf handler can be used as so:
```dart
import 'package:meg/meg.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() async {
  /* define your variables */ 
  
  final server = await shelf_io.serve(
    megHandler(
      s3Uri,
      region: region,
      accessKey: accessKey,
      secretKey: secretKey,
      bucket: bucket,
    ),
    host ?? InternetAddress.anyIPv4.address,
    port,
  );
}
```

Meg also has some useful functions for working with the `Archive` type in other cases, such as converting archives into a usable, read-only file system for use with [`package:file`](https://pub.dev/packages/file).

```dart
import 'package:meg/meg.dart';

void main() async {
  final List<int> archiveData = <int>[/* data */];
  final archive = ZipArchiveFormat().convert(archiveData);
  
  final fs = archiveToFileSystem(archive);
  
  // perform file operations
  print(await archive.file('foo.txt').readAsBytes());
}
```