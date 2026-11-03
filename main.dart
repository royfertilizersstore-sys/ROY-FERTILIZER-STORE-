
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:bcrypt/bcrypt.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StoreDb.instance.db;
  runApp(const RoyApp());
}

class StoreDb {
  StoreDb._();
  static final instance = StoreDb._();
  Database? _database;
  Future<Database> get db async {
    if (_database != null) return _database!;
    final path = p.join(await getDatabasesPath(), 'roy_store_v2.db');
    _database = await openDatabase(path, version: 2, onCreate: (d, v) async {
      await d.execute('CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, unit TEXT, stock REAL, buy REAL, sell REAL)');
      await d.execute('CREATE TABLE parties(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, name TEXT, phone TEXT, address TEXT, gstin TEXT)');
      await d.execute('CREATE TABLE entries(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, product_id INTEGER, party TEXT, qty REAL, rate REAL, total REAL, note TEXT, created_at TEXT, sync_status TEXT DEFAULT "pending")');
      await d.execute("CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('Admin','Staff')), active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
      for (final row in [
        {'name':'Urea','unit':'45 kg bag','stock':0.0,'buy':0.0,'sell':0.0},
        {'name':'SSP','unit':'50 kg bag','stock':0.0,'buy':0.0,'sell':0.0},
        {'name':'DAP','unit':'50 kg bag','stock':0.0,'buy':0.0,'sell':0.0},
        {'name':'NPK','unit':'50 kg bag','stock':0.0,'buy':0.0,'sell':0.0},
      ]) { await d.insert('products', row); }
    }, onUpgrade: (d, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await d.execute("CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('Admin','Staff')), active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL)");
      }
    });
    return _database!;
  }

  Future<int> userCount() async => Sqflite.firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM users')) ?? 0;
  Future<Map<String,Object?>?> findUser(String username) async {
    final rows = await (await db).query('users', where:'username=? COLLATE NOCASE', whereArgs:[username.trim()]);
    return rows.isEmpty ? null : rows.first;
  }
  Future<void> createUser(String username, String password, String role) async {
    final hash = BCrypt.hashpw(password, BCrypt.gensalt());
    await (await db).insert('users', {'username':username.trim(),'password_hash':hash,'role':role,'active':1,'created_at':DateTime.now().toIso8601String()});
  }
  Future<bool> verifyUser(String username, String password) async {
    final u = await findUser(username);
    if (u == null || (u['active'] as int) != 1) return false;
    return BCrypt.checkpw(password, u['password_hash'] as String);
  }
  Future<List<Map<String,Object?>>> users() async => (await db).query('users', orderBy:'role, username');
  Future<void> setUserActive(int id, bool active) async => (await db).update('users', {'active':active?1:0}, where:'id=? AND role=?', whereArgs:[id,'Staff']);
  Future<void> changePassword(int id, String password) async {
    final hash=BCrypt.hashpw(password, BCrypt.gensalt());
    await (await db).update('users', {'password_hash':hash}, where:'id=?', whereArgs:[id]);
  }

  Future<List<Map<String,Object?>>> products() async => (await db).query('products', orderBy:'name');
  Future<List<Map<String,Object?>>> entries() async => (await db).rawQuery('SELECT e.*,p.name product FROM entries e LEFT JOIN products p ON p.id=e.product_id ORDER BY e.id DESC');
  Future<List<Map<String,Object?>>> parties(String type) async => (await db).query('parties', where:'type=?', whereArgs:[type], orderBy:'name');

  Future<void> addProduct(String name, String unit, double buy, double sell) async {
    await (await db).insert('products', {'name':name,'unit':unit,'stock':0,'buy':buy,'sell':sell});
  }
  Future<void> addParty(String type,String name,String phone,String address,String gstin) async {
    await (await db).insert('parties', {'type':type,'name':name,'phone':phone,'address':address,'gstin':gstin});
  }
  Future<void> entry(String type,int productId,String party,double qty,double rate,String note) async {
    final d=await db;
    await d.transaction((tx) async {
      final rows=await tx.query('products',where:'id=?',whereArgs:[productId]);
      if(rows.isEmpty) throw Exception('Product not found');
      final old=(rows.first['stock'] as num).toDouble();
      final next=type=='Sale'?old-qty:old+qty;
      if(qty<=0 || next<0) throw Exception('Invalid quantity or insufficient stock');
      await tx.update('products',{'stock':next, if(type=='Sale') 'sell':rate, if(type=='Purchase') 'buy':rate},where:'id=?',whereArgs:[productId]);
      await tx.insert('entries',{'type':type,'product_id':productId,'party':party,'qty':qty,'rate':rate,'total':qty*rate,'note':note,'created_at':DateTime.now().toIso8601String(),'sync_status':'pending'});
    });
  }
  Future<Map<String,double>> totals() async {
    final rows=await (await db).rawQuery('SELECT type,SUM(total) amount FROM entries GROUP BY type');
    final out=<String,double>{'Sale':0,'Purchase':0};
    for(final r in rows){out[r['type'] as String]=(r['amount'] as num).toDouble();}
    return out;
  }
}

class RoyApp extends StatelessWidget {
  const RoyApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(
    title:'ROY FERTILIZER STORE',debugShowCheckedModeBanner:false,
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF237A43)),useMaterial3:true,scaffoldBackgroundColor:const Color(0xFFF4F7F4)),
    home:const AuthGate());
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override State<AuthGate> createState()=>_AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  Future<int>? count;
  @override void initState(){super.initState();count=StoreDb.instance.userCount();}
  void refresh()=>setState(()=>count=StoreDb.instance.userCount());
  @override Widget build(BuildContext context)=>FutureBuilder<int>(future:count,builder:(c,s){
    if(!s.hasData)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return s.data==0?SetupAdminPage(onCreated:refresh):LoginPage(onLogin:(u){Navigator.of(context).pushReplacement(MaterialPageRoute(builder:(_)=>Home(user:u)));});
  });
}

class SetupAdminPage extends StatefulWidget {
  final VoidCallback onCreated;
  const SetupAdminPage({super.key,required this.onCreated});
  @override State<SetupAdminPage> createState()=>_SetupAdminPageState();
}
class _SetupAdminPageState extends State<SetupAdminPage>{
  final username=TextEditingController(),password=TextEditingController(),confirm=TextEditingController(); bool busy=false,show=false;
  Future<void> save() async {
    if(username.text.trim().length<3||password.text.length<10||password.text!=confirm.text){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Use a username of 3+ characters and matching passwords of at least 10 characters.')));return;}
    setState(()=>busy=true);
    try{await StoreDb.instance.createUser(username.text,password.text,'Admin');widget.onCreated();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not create Admin: $e')));}
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Card(child:Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Icon(Icons.agriculture,size:48,color:Color(0xFF237A43)),const SizedBox(height:10),const Text('ROY FERTILIZER STORE',textAlign:TextAlign.center,style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('Create the first Admin account',textAlign:TextAlign.center),const SizedBox(height:20),
    TextField(controller:username,autocorrect:false,decoration:const InputDecoration(labelText:'Admin username',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:password, obscureText:!show,decoration:const InputDecoration(labelText:'Password (minimum 10 characters)',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:confirm,obscureText:!show,decoration:const InputDecoration(labelText:'Confirm password',border:OutlineInputBorder())),CheckboxListTile(value:show,onChanged:(v)=>setState(()=>show=v??false),contentPadding:EdgeInsets.zero,title:const Text('Show passwords')),const SizedBox(height:8),FilledButton(onPressed:busy?null:save,child:Text(busy?'Creating…':'Create Admin account')),
    const Text('Keep your password private. It cannot be recovered if lost.',style:TextStyle(fontSize:11,color:Colors.black54),textAlign:TextAlign.center)
  ]))))));
}

class LoginPage extends StatefulWidget {
  final ValueChanged<Map<String,Object?>> onLogin;
  const LoginPage({super.key,required this.onLogin});
  @override State<LoginPage> createState()=>_LoginPageState();
}
class _LoginPageState extends State<LoginPage>{
  final username=TextEditingController(),password=TextEditingController(); bool busy=false,show=false;
  Future<void> login() async {
    if(username.text.trim().isEmpty||password.text.isEmpty)return;
    setState(()=>busy=true);
    try{final ok=await StoreDb.instance.verifyUser(username.text,password.text);if(ok){final u=await StoreDb.instance.findUser(username.text);if(u!=null&&mounted)widget.onLogin(u);}else if(mounted){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Incorrect username/password or account disabled.')));}}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Login failed: $e')));}
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Card(child:Padding(padding:const EdgeInsets.all(22),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Icon(Icons.lock_person,size:48,color:Color(0xFF237A43)),const SizedBox(height:10),const Text('ROY FERTILIZER STORE',textAlign:TextAlign.center,style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Text('Sign in to continue',textAlign:TextAlign.center),const SizedBox(height:22),TextField(controller:username,autocorrect:false,decoration:const InputDecoration(labelText:'Username',border:OutlineInputBorder()),onSubmitted:(_)=>login()),const SizedBox(height:12),TextField(controller:password,obscureText:!show,decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder()),onSubmitted:(_)=>login()),CheckboxListTile(value:show,onChanged:(v)=>setState(()=>show=v??false),contentPadding:EdgeInsets.zero,title:const Text('Show password')),FilledButton(onPressed:busy?null:login,child:Text(busy?'Signing in…':'Login')),
  ]))))));
}

class Home extends StatefulWidget {
  final Map<String,Object?> user;
  const Home({super.key,required this.user});
  @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> {
  int tab=0; bool assamese=true;
  bool get isAdmin => widget.user['role']=='Admin';
  String t(String en,String as)=>assamese?as:en;
  final db=StoreDb.instance;
  @override Widget build(BuildContext context){
    final pages=isAdmin?[dashboard(),stockPage(),salesPage(),partyPage(),reportPage()]:[dashboard(),salesPage(),partyPage()];
    if(tab>=pages.length)tab=0;
    return Scaffold(
      appBar:AppBar(backgroundColor:const Color(0xFF14532D),foregroundColor:Colors.white,title:const Text('ROY FERTILIZER STORE',style:TextStyle(fontSize:16,fontWeight:FontWeight.bold)),actions:[if(isAdmin)IconButton(tooltip:'Manage staff',onPressed:manageStaff,icon:const Icon(Icons.manage_accounts)),IconButton(tooltip:'Change password',onPressed:changeMyPassword,icon:const Icon(Icons.key)),TextButton(onPressed:()=>setState(()=>assamese=!assamese),child:Text(assamese?'EN':'অসমীয়া',style:const TextStyle(color:Colors.white))),IconButton(tooltip:'Logout',onPressed:()=>Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const AuthGate()),(r)=>false),icon:const Icon(Icons.logout))]),
      body:pages[tab],
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:isAdmin?[
        NavigationDestination(icon:const Icon(Icons.dashboard),label:t('Home','হোম')),
        NavigationDestination(icon:const Icon(Icons.inventory_2),label:t('Stock','ষ্টক')),
        NavigationDestination(icon:const Icon(Icons.receipt_long),label:t('Sales','বিক্ৰী')),
        NavigationDestination(icon:const Icon(Icons.people),label:t('Parties','গ্ৰাহক')),
        NavigationDestination(icon:const Icon(Icons.bar_chart),label:t('Reports','ৰিপৰ্ট')),
      ]:[
        NavigationDestination(icon:const Icon(Icons.dashboard),label:t('Home','হোম')),
        NavigationDestination(icon:const Icon(Icons.receipt_long),label:t('Sales','বিক্ৰী')),
        NavigationDestination(icon:const Icon(Icons.people),label:t('Customers','গ্ৰাহক')),
      ]));
  }

  Future<void> changeMyPassword() async {
    final old=TextEditingController(),next=TextEditingController(),confirm=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Change password'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:old,obscureText:true,decoration:const InputDecoration(labelText:'Current password')),TextField(controller:next,obscureText:true,decoration:const InputDecoration(labelText:'New password (10+ characters)')),TextField(controller:confirm,obscureText:true,decoration:const InputDecoration(labelText:'Confirm new password'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()async{
      final valid=await db.verifyUser(widget.user['username'] as String,old.text);
      if(!valid||next.text.length<10||next.text!=confirm.text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Check current password and ensure the new passwords match (10+ characters).')));return;}
      await db.changePassword(widget.user['id'] as int,next.text);if(ctx.mounted)Navigator.pop(ctx);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Password updated.')));
    },child:const Text('Update'))]));
  }

  Future<void> manageStaff() async {
    final name=TextEditingController(),pass=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,sd)=>AlertDialog(title:const Text('Staff accounts'),content:SizedBox(width:360,child:Column(mainAxisSize:MainAxisSize.min,children:[
      FutureBuilder<List<Map<String,Object?>>>(future:db.users(),builder:(c,s)=>ConstrainedBox(constraints:const BoxConstraints(maxHeight:180),child:ListView(shrinkWrap:true,children:(s.data??[]).where((u)=>u['role']=='Staff').map<Widget>((u)=>SwitchListTile(title:Text('${u['username']}'),subtitle:Text((u['active'] as int)==1?'Active':'Disabled'),value:(u['active'] as int)==1,onChanged:(v)async{await db.setUserActive(u['id'] as int,v);sd((){});}).toList())))),const Divider(),TextField(controller:name,decoration:const InputDecoration(labelText:'New staff username')),TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'Temporary password (10+ characters)')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close')),FilledButton(onPressed:()async{if(name.text.trim().length<3||pass.text.length<10){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Username must be 3+ characters and password 10+ characters.')));return;}try{await db.createUser(name.text,pass.text,'Staff');name.clear();pass.clear();sd((){});}catch(e){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not add staff: $e')));}},child:const Text('Add staff'))]));
  }

  Widget dashboard()=>FutureBuilder<List<Map<String,Object?>>>(future:db.products(),builder:(c,s){
    final rows=s.data??[]; final total=rows.fold<double>(0,(a,r)=>a+(r['stock'] as num).toDouble());
    return ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(20),gradient:const LinearGradient(colors:[Color(0xFF14532D),Color(0xFF35965A)])),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(Icons.agriculture,color:Colors.white,size:36),SizedBox(height:8),
        Text('Smart Fertilizer Management',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.bold)),
        Text('PARIMAL KUMAR ROY • KAIMARI, AGOMONI, DHUBRI',style:TextStyle(color:Colors.white70,fontSize:11)),
        Text('Offline-first shop management',style:TextStyle(color:Colors.white)),
      ]),])),
      const SizedBox(height:14),
      Row(children:[Expanded(child:metric(t('Total stock','মুঠ ষ্টক'),'${total.toStringAsFixed(0)} bags',Icons.inventory)),const SizedBox(width:10),Expanded(child:metric(t('Products','সামগ্ৰী'),'${rows.length}',Icons.category))]),
      const SizedBox(height:16),Text(t('Stock overview','ষ্টকৰ বিৱৰণ'),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      ...rows.map(productTile),
      const Padding(padding:EdgeInsets.only(top:8),child:Text('Local data is saved on this device. Cloud sync requires a configured backend.',style:TextStyle(fontSize:11,color:Colors.black54))),
    ]);
  });

  Widget metric(String title,String value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:const Color(0xFF237A43)),const SizedBox(height:8),Text(value,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text(title,style:const TextStyle(fontSize:12,color:Colors.black54))])));
  Widget productTile(Map<String,Object?> r)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.grass)),title:Text('${r['name']}',style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(isAdmin?'${r['unit']} • Buy ₹${r['buy']} • Sell ₹${r['sell']}':'${r['unit']} • Sell ₹${r['sell']}'),trailing:Text('${(r['stock'] as num).toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18))));

  Widget stockPage()=>FutureBuilder<List<Map<String,Object?>>>(future:db.products(),builder:(c,s){
    final rows=s.data??[];
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text(t('Inventory / Stock','ষ্টক পৰিচালনা'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      ...rows.map(productTile),
      if(isAdmin)FilledButton.icon(onPressed:addProductDialog,icon:const Icon(Icons.add),label:Text(t('Add product','সামগ্ৰী যোগ কৰক'))),
      if(isAdmin)OutlinedButton.icon(onPressed:()=>entryDialog('Purchase',rows),icon:const Icon(Icons.add_box),label:Text(t('Purchase / Stock in','ক্ৰয় / ষ্টক যোগ'))),
    ]);
  });

  Future<void> addProductDialog()async{
    final n=TextEditingController(),u=TextEditingController(text:'50 kg bag'),b=TextEditingController(text:'0'),s=TextEditingController(text:'0');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:Text(t('Add product','সামগ্ৰী যোগ কৰক')),content:Column(mainAxisSize:MainAxisSize.min,children:[field(n,'Product name'),field(u,'Unit'),field(b,'Purchase rate',num:true),field(s,'Sale rate',num:true)]),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
      FilledButton(onPressed:()async{if(n.text.trim().isNotEmpty){try{await db.addProduct(n.text.trim(),u.text,double.tryParse(b.text)??0,double.tryParse(s.text)??0);}catch(_){}}if(ctx.mounted)Navigator.pop(ctx);setState((){});},child:const Text('Save'))]));
  }

  Widget salesPage()=>FutureBuilder<List<Map<String,Object?>>>(future:db.entries(),builder:(c,s){
    final rows=(s.data??[]).where((r)=>isAdmin||r['type']=='Sale').toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text(t('Sales & Purchase','বিক্ৰী আৰু ক্ৰয়'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      FutureBuilder<List<Map<String,Object?>>>(future:db.products(),builder:(c,p)=>FilledButton.icon(onPressed:()=>entryDialog('Sale',p.data??[]),icon:const Icon(Icons.point_of_sale),label:Text(t('New sale & invoice','নতুন বিক্ৰী আৰু ইনভইচ')))),
      ...rows.map((r)=>Card(child:ListTile(leading:Icon(r['type']=='Sale'?Icons.shopping_cart:Icons.local_shipping),title:Text('${r['type']} • ${r['product']}'),subtitle:Text('${r['party']} • ${r['qty']} × ₹${r['rate']}'),trailing:Text('₹${(r['total'] as num).toStringAsFixed(2)}')))),
    ]);
  });

  Future<void> entryDialog(String type,List<Map<String,Object?>> products)async{
    if(products.isEmpty)return;
    int productId=products.first['id'] as int;
    final party=TextEditingController(),q=TextEditingController(),rate=TextEditingController(text:'0'),note=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,sd)=>AlertDialog(
      title:Text(type=='Sale'?t('New sale','নতুন বিক্ৰী'):t('New purchase','নতুন ক্ৰয়')),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<int>(value:productId,items:products.map((p)=>DropdownMenuItem(value:p['id'] as int,child:Text('${p['name']} (stock ${(p['stock'] as num).toStringAsFixed(0)})'))).toList(),onChanged:(v){if(v!=null)sd(()=>productId=v);},decoration:InputDecoration(labelText:t('Product','সামগ্ৰী'))),
        field(party,type=='Sale'?'Customer name':'Supplier name'),field(q,'Quantity (bags)',num:true),field(rate,'Rate per bag (₹)',num:true),field(note,'Note (optional)'),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()async{
        final qty=double.tryParse(q.text),price=double.tryParse(rate.text);
        if(qty==null||price==null)return;
        try{
          await db.entry(type,productId,party.text,qty,price,note.text);
          if(type=='Sale')await makeInvoice(party.text,products.firstWhere((x)=>x['id']==productId)['name'].toString(),qty,price);
          if(ctx.mounted)Navigator.pop(ctx);setState((){});
        }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
      },child:const Text('Save'))],
    )));
  }

  Future<void> makeInvoice(String customer,String item,double qty,double rate)async{
    final doc=pw.Document(); final total=qty*rate;
    doc.addPage(pw.Page(build:(c)=>pw.Padding(padding:const pw.EdgeInsets.all(28),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
      pw.Text('ROY FERTILIZER STORE',style:pw.TextStyle(fontSize:22,fontWeight:pw.FontWeight.bold)),
      pw.Text('Kaimari, Agomoni, Dhubri, Assam'),pw.SizedBox(height:18),
      pw.Text('SALES INVOICE',style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)),
      pw.Text('Invoice: ROY-${DateTime.now().millisecondsSinceEpoch}'),
      pw.Text('Date: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}'),
      pw.Text('Customer: $customer'),pw.SizedBox(height:18),
      pw.TableHelper.fromTextArray(headers:['Item','Qty','Rate','Amount'],data:[[item,'$qty','₹${rate.toStringAsFixed(2)}','₹${total.toStringAsFixed(2)}']]),
      pw.Spacer(),pw.Align(alignment:pw.Alignment.centerRight,child:pw.Text('Total: ₹${total.toStringAsFixed(2)}',style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold))),
      pw.SizedBox(height:20),pw.Text('Thank you for your purchase!'),
    ]))));
    await Printing.layoutPdf(onLayout:(_)=>doc.save());
  }

  Widget partyPage()=>ListView(padding:const EdgeInsets.all(16),children:[
    Text(t('Customers & Suppliers','গ্ৰাহক আৰু যোগানকাৰী'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    FilledButton.icon(onPressed:()=>partyDialog('Customer'),icon:const Icon(Icons.person_add),label:Text(t('Add customer','গ্ৰাহক যোগ কৰক'))),
    if(isAdmin)OutlinedButton.icon(onPressed:()=>partyDialog('Supplier'),icon:const Icon(Icons.local_shipping),label:Text(t('Add supplier','যোগানকাৰী যোগ কৰক'))),
    partyList('Customer'),if(isAdmin)partyList('Supplier'),
  ]);
  Widget partyList(String type)=>FutureBuilder<List<Map<String,Object?>>>(future:db.parties(type),builder:(c,s)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const SizedBox(height:12),Text(type=='Customer'?t('Customers','গ্ৰাহক'):t('Suppliers','যোগানকাৰী'),style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
    ...(s.data??[]).map((r)=>Card(child:ListTile(title:Text('${r['name']}'),subtitle:Text('${r['phone']} • ${r['address']}')))),
  ]));
  Future<void> partyDialog(String type)async{
    final n=TextEditingController(),ph=TextEditingController(),a=TextEditingController(),g=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:Text('Add $type'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[field(n,'Name'),field(ph,'Phone'),field(a,'Address'),field(g,'GSTIN (optional)')])),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),
      FilledButton(onPressed:()async{if(n.text.trim().isNotEmpty)await db.addParty(type,n.text,ph.text,a.text,g.text);if(ctx.mounted)Navigator.pop(ctx);setState((){});},child:const Text('Save'))]));
  }

  Widget reportPage()=>FutureBuilder<Map<String,double>>(future:db.totals(),builder:(c,s){
    final r=s.data??{'Sale':0.0,'Purchase':0.0};
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text(t('Business Reports','ব্যৱসায়িক ৰিপৰ্ট'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      Card(child:Column(children:[
        ListTile(title:Text(t('Recorded sales','মুঠ বিক্ৰী')),trailing:Text('₹${(r['Sale']??0).toStringAsFixed(2)}')),
        ListTile(title:Text(t('Recorded purchases','মুঠ ক্ৰয়')),trailing:Text('₹${(r['Purchase']??0).toStringAsFixed(2)}')),
        ListTile(title:Text(t('Sales minus purchases (not net profit)','বিক্ৰী-ক্ৰয় (নিট লাভ নহয়)')),trailing:Text('₹${((r['Sale']??0)-(r['Purchase']??0)).toStringAsFixed(2)}')),
      ])),
      const Text('Summary excludes operating expenses, taxes, returns and opening inventory valuation.',style:TextStyle(fontSize:11,color:Colors.black54)),
    ]);
  });

  Widget field(TextEditingController c,String label,{bool num=false})=>Padding(padding:const EdgeInsets.only(bottom:8),child:TextField(controller:c,keyboardType:num?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
}
