/**
 * Error thrown by the runtime system when an custom fails.
 */
class CustomError extends Error {
  /** Message describing the error. */
  final Object message;

  CustomError([this.message]);

  String toString() => '${message ?? 'Unknown error'}';
}
