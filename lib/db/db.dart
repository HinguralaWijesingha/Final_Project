import 'package:safe_pulse/model/contactdb.dart';
import 'package:safe_pulse/model/message_model.dart';
import 'package:sqflite/sqflite.dart';

class DB {
  // Contact table
  String contactTable = 'contacts_table';
  String contactid = 'id';
  String contactName = 'name';
  String contactNumber = 'number';

  // Message table
  String messageTable = 'messages_table';
  String messageId = 'id';
  String messageContactId = 'contact_id';
  String messageContent = 'content';
  String messageTimestamp = 'timestamp';
  String messageIsFromMe = 'is_from_me';

  DB._createInstance();

  static DB? _db;

  factory DB() {
    _db ??= DB._createInstance();
    return _db!;
  }

  static Database? _database;
  Future<Database> get database async {
    _database ??= await initializeDatabase();
    return _database!;
  }

  Future<Database> initializeDatabase() async {
    String path = await getDatabasesPath();
    String location = '${path}contacts.db';

    var contactDb = await openDatabase(location, version: 2, onCreate: _createDbTable, onUpgrade: _upgradeDb);
    return contactDb;
  }

  void _createDbTable(Database db, int version) async {
    // Create contacts table
    await db.execute('CREATE TABLE $contactTable($contactid INTEGER PRIMARY KEY AUTOINCREMENT, $contactName TEXT, $contactNumber TEXT)');
    
    // Create messages table
    await db.execute('''
      CREATE TABLE $messageTable(
        $messageId INTEGER PRIMARY KEY AUTOINCREMENT, 
        $messageContactId INTEGER, 
        $messageContent TEXT, 
        $messageTimestamp TEXT,
        $messageIsFromMe INTEGER,
        FOREIGN KEY ($messageContactId) REFERENCES $contactTable($contactid) ON DELETE CASCADE
      )
    ''');
  }

  void _upgradeDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Create messages table if upgrading from version 1
      await db.execute('''
        CREATE TABLE $messageTable(
          $messageId INTEGER PRIMARY KEY AUTOINCREMENT, 
          $messageContactId INTEGER, 
          $messageContent TEXT, 
          $messageTimestamp TEXT,
          $messageIsFromMe INTEGER,
          FOREIGN KEY ($messageContactId) REFERENCES $contactTable($contactid) ON DELETE CASCADE
        )
      ''');
    }
  }

  // Contact methods
  Future<List<Map<String, dynamic>>> getContactMapList() async {
    Database db = await database;
    List<Map<String, dynamic>> result = await db.rawQuery('SELECT * FROM $contactTable ORDER BY $contactid ASC');
    return result;
  }

  Future<int> insertContact(Dcontacts contact) async {
    Database db = await database;
    var result = await db.insert(contactTable, contact.toMap());
    return result;
  }

  Future<int> updateContact(Dcontacts contact) async {
    Database db = await database;
    var result = await db.update(contactTable, contact.toMap(), where: '$contactid = ?', whereArgs: [contact.id]);
    return result;
  }

  Future<int> deleteContact(int id) async {
    Database db = await database;
    int result = await db.rawDelete('DELETE FROM $contactTable WHERE $contactid = $id');
    return result;
  }

  Future<int> getCount() async {
    Database db = await database;
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
  
  Future<Dcontacts> getContactById(int id) async {
    Database db = await database;
    List<Map<String, dynamic>> result = await db.query(
      contactTable,
      where: '$contactid = ?',
      whereArgs: [id]
    );
    
    if (result.isNotEmpty) {
      return Dcontacts.fromMapObject(result.first);
    } else {
      throw Exception('Contact not found');
    }
  }

  // Message methods
  Future<int> insertMessage(Message message) async {
    Database db = await database;
    var result = await db.insert(messageTable, message.toMap());
    return result;
  }

  Future<List<Message>> getMessagesForContact(int contactId) async {
    Database db = await database;
    List<Map<String, dynamic>> result = await db.query(
      messageTable,
      where: '$messageContactId = ?',
      whereArgs: [contactId],
      orderBy: '$messageTimestamp ASC'
    );
    
    List<Message> messages = <Message>[];
    for (var map in result) {
      messages.add(Message.fromMapObject(map));
    }
    return messages;
  }

  Future<int> deleteAllMessagesForContact(int contactId) async {
    Database db = await database;
    int result = await db.delete(
      messageTable,
      where: '$messageContactId = ?',
      whereArgs: [contactId]
    );
    return result;
  }
}