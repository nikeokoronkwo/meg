class BucketNotification {
  final BucketChange change;
  final String path;
  final String? eTag;

  const BucketNotification(this.change, this.path, [this.eTag]);
}

final class BucketChange {
  final String change;

  const BucketChange(this.change);

  static const BucketChange delete = BucketChange('delete');
  static const BucketChange create = BucketChange('create');
  static const BucketChange modify = BucketChange('modify');
}
