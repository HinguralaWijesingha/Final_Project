class Dcontacts {
  int? _id;
  String? _number;
  String? _name;

  Dcontacts(this._name, this._number);
  Dcontacts.withId(this._id, this._name, this._number);

  int get id => _id!;
  String get name => _name!;
  String get number => _number!;

  @override
  String toString() {
    return 'Dcontacts{_id: $_id, _name: $_name, _number: $_number}';
  }

  set number(String newNumber) => _number = newNumber;
  set name(String newName) => _name = newName;

  Map<String, dynamic> toMap() {
    var map = new Map<String, dynamic>();

    map['id'] = _id;
    map['name'] = _name;
    map['number'] = _number;

    return map;
  }

  Dcontacts.fromMapObject(Map<String, dynamic> map) {
    _id = map['id'];
    _name = map['name'];
    _number = map['number'];
  }
}
