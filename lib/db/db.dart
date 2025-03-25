import 'package:safe_pulse/model/contactdb.dart';
import 'package:sqflite/sqflite.dart';

class DB {
  String contactTable = 'contacts_table';
  String contactid = 'id';
  String contactName = 'name';
  String contactNumber = 'number';

  DB._createInstance();

  static DB? _db;

  factory DB() {
    if (_db == null) {
      _db = DB._createInstance();
    }
    return _db!;
  }

  static Database? _database;
  Future<Database> get database async {
    if (_database == null) {
      _database = await initializeDatabase();
    }
    return _database!;
  }

  Future<Database> initializeDatabase() async {
    String path = await getDatabasesPath();
    String location = path + 'contacts.db';

    var contactDb = await openDatabase(location, version: 1, onCreate: _createDbTable);
    return contactDb;
  }

  void _createDbTable(Database db, int version) async {
    await db.execute('CREATE TABLE $contactTable($contactid INTEGER PRIMARY KEY AUTOINCREMENT, $contactName TEXT, $contactNumber TEXT)');
  }

  Future<List<Map<String, dynamic>>> getContactMapList() async {
    Database db = await this.database;
    List<Map<String, dynamic>> result = await db.rawQuery('SELECT * FROM $contactTable ORDER BY $contactid ASC');
    return result;
  }

  Future<int> insertContact(Dcontacts contact) async {
    Database db = await this.database;
    var result = await db.insert(contactTable, contact.toMap());
    return result;
  }

  Future<int> updateContact(Dcontacts contact) async {
    Database db = await this.database;
    var result = await db.update(contactTable, contact.toMap(), where: '$contactid = ?', whereArgs: [contact.id]);
    return result;
  }

  Future<int> deleteContact(int id) async {
    Database db = await this.database;
    int result = await db.rawDelete('DELETE FROM $contactTable WHERE $contactid = $id');
    return result;
  }

  Future<int> getCount() async {
    Database db = await this.database;
    List<Map<String, dynamic>> x = await db.rawQuery('SELECT COUNT (*) from $contactTable');
    int result = Sqflite.firstIntValue(x)!;
    return result;
  }

  Future<List<Dcontacts>> getContacts() async {
    var contactMapList = await getContactMapList();
    int count = contactMapList.length;

    List<Dcontacts> contacts = <Dcontacts>[];
    
    for (int i = 0; i < count; i++) {
      contacts.add(Dcontacts.fromMapObject(contactMapList[i]));
  }
    return contacts;
    
  }



}
