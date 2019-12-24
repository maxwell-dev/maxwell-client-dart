class Event {
  final int _eventId;
  final dynamic _extra;
  static const Event ON_CONNECTING = const Event._(100);
  static const Event ON_CONNECTED = const Event._(101);
  static const Event ON_DISCONNECTING = const Event._(102);
  static const Event ON_DISCONNECTED = const Event._(103);
  static const Event ON_MESSAGE = const Event._(104);

  const Event._(int eventId, [dynamic extra])
      : _eventId = eventId,
        _extra = extra;

  const Event.error(dynamic extra) : this._(105, extra);

  bool operator ==(other) =>
      other is Event &&
      this._eventId == other._eventId &&
      this._extra == other._extra;

  int get hashCode => this._eventId.hashCode ^ this._extra.hashCode;
}
