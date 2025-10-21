T? tryOrNull<T>(T Function() computation) {
  try {
    return computation();
  } catch (e) {
    return null;
  }
}

T tryOrElse<T>(T Function() computation, T orElse) {
  try {
    return computation();
  } catch (e) {
    return orElse;
  }
}
