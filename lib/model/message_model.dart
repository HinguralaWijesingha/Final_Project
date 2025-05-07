class Message {
  int? _id;
  int? _contactId;
  String? _content;
  String? _timestamp;
  bool? _isFromMe;

  Message(this._contactId, this._content, this._timestamp, this._isFromMe);
  Message.withId(this._id, this._contactId, this._content, this._timestamp, this._isFromMe);

  int get id => _id!;
  int get contactId => _contactId!;
  String get content => _content!;
  String get timestamp => _timestamp!;
  bool get isFromMe => _isFromMe!;

  set contactId(int newContactId) => _contactId = newContactId;
  set content(String newContent) => _content = newContent;
  set timestamp(String newTimestamp) => _timestamp = newTimestamp;
  set isFromMe(bool newIsFromMe) => _isFromMe = newIsFromMe;

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{};
    
    if (_id != null) {
      map['id'] = _id;
    }
    map['contact_id'] = _contactId;
    map['content'] = _content;
    map['timestamp'] = _timestamp;
    map['is_from_me'] = _isFromMe! ? 1 : 0;

    return map;
  }

  Message.fromMapObject(Map<String, dynamic> map) {
    _id = map['id'];
    _contactId = map['contact_id'];
    _content = map['content'];
    _timestamp = map['timestamp'];
    _isFromMe = map['is_from_me'] == 1;
  }

  @override
  String toString() {
    return 'Message{_id: $_id, _contactId: $_contactId, _content: $_content, _timestamp: $_timestamp, _isFromMe: $_isFromMe}';
  }
}