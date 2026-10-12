import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const StudyOSApp());
}

class StudyOSApp extends StatelessWidget {
  const StudyOSApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'StudyOS',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6558D3), brightness: Brightness.dark),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF10111A),
      cardTheme: CardThemeData(color: const Color(0xFF1A1C29), elevation: 0, margin: EdgeInsets.zero),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: const Color(0xFF222436),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    ),
    home: const HomePage(),
  );
}

class StudyNote {
  String subject, title, body;
  StudyNote(this.subject, this.title, this.body);
  Map<String, dynamic> toJson() => {'subject': subject, 'title': title, 'body': body};
  factory StudyNote.fromJson(Map<String, dynamic> j) => StudyNote(j['subject'] ?? 'Other', j['title'] ?? '', j['body'] ?? '');
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int tab = 0;
  late SharedPreferences prefs;
  bool ready = false;
  final schoolStart = TextEditingController(text: '06:00');
  final schoolEnd = TextEditingController(text: '14:30');
  final tuitionStart = TextEditingController(text: '18:00');
  final tuitionEnd = TextEditingController(text: '19:00');
  final wake = TextEditingController(text: '05:15');
  final bedtime = TextEditingController(text: '22:00');
  final noteTitle = TextEditingController();
  final noteBody = TextEditingController();
  String noteSubject = 'Mathematics';
  List<StudyNote> notes = [];
  String goal = 'Revise one topic and solve 10 questions';
  final goalController = TextEditingController(text: 'Revise one topic and solve 10 questions');
  int focusMinutes = 25;
  int secondsLeft = 25 * 60;
  bool timerRunning = false;
  Timer? timer;
  int completedSessions = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    prefs = await SharedPreferences.getInstance();
    schoolStart.text = prefs.getString('schoolStart') ?? '06:00';
    schoolEnd.text = prefs.getString('schoolEnd') ?? '14:30';
    tuitionStart.text = prefs.getString('tuitionStart') ?? '18:00';
    tuitionEnd.text = prefs.getString('tuitionEnd') ?? '19:00';
    wake.text = prefs.getString('wake') ?? '05:15';
    bedtime.text = prefs.getString('bedtime') ?? '22:00';
    goalController.text = prefs.getString('goal') ?? goal;
    goal = goalController.text;
    completedSessions = prefs.getInt('completedSessions') ?? 0;
    final raw = prefs.getString('notes') ?? '[]';
    try { notes = (jsonDecode(raw) as List).map((e) => StudyNote.fromJson(Map<String,dynamic>.from(e))).toList(); } catch (_) { notes = []; }
    if (mounted) setState(() => ready = true);
  }

  Future<void> _saveHours() async {
    await prefs.setString('schoolStart', schoolStart.text);
    await prefs.setString('schoolEnd', schoolEnd.text);
    await prefs.setString('tuitionStart', tuitionStart.text);
    await prefs.setString('tuitionEnd', tuitionEnd.text);
    await prefs.setString('wake', wake.text);
    await prefs.setString('bedtime', bedtime.text);
  }

  Future<void> _saveNotes() async {
    await prefs.setString('notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final c in [schoolStart, schoolEnd, tuitionStart, tuitionEnd, wake, bedtime, noteTitle, noteBody, goalController]) { c.dispose(); }
    super.dispose();
  }

  int? _mins(String s) {
    final p = s.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }
  String _clock(int mins) {
    mins = mins % 1440;
    return '${(mins ~/ 60).toString().padLeft(2,'0')}:${(mins % 60).toString().padLeft(2,'0')}';
  }

  List<Map<String,String>> _routine() {
    final ss = _mins(schoolStart.text), se = _mins(schoolEnd.text);
    final ts = _mins(tuitionStart.text), te = _mins(tuitionEnd.text);
    final w = _mins(wake.text), b = _mins(bedtime.text);
    if ([ss,se,ts,te,w,b].any((v) => v == null)) return [{'time':'Check your times','title':'Use 24-hour HH:MM format','desc':'Example: 06:00'}];
    if (se! <= ss! || te! <= ts! || b! <= w! || (ss < te && ts < se)) {
      return [{'time':'Check your schedule','title':'Some times overlap or are invalid','desc':'School and tuition should not overlap; end times must be later than start times.'}];
    }
    final items = <Map<String,String>>[];
    void add(int start, int end, String title, String desc) {
      if (end - start >= 10) items.add({'time':'${_clock(start)}–${_clock(end)}','title':title,'desc':desc,'_start':'$start'});
    }
    add(w!, ss, 'Morning routine & quick recall', 'Get ready and review formulas or definitions.');
    add(se, se+30, 'Lunch, travel & reset', 'Eat and decompress after school.');
    final freeStart = se + 30;
    if (ts - freeStart >= 55) {
      add(freeStart, freeStart+20, 'Rest & snack', 'Recharge before studying.');
      add(freeStart+20, ts, 'Focused study', 'Homework or your weakest subject.');
    } else if (ts - freeStart >= 10) {
      add(freeStart, ts, 'Rest / quick review', 'Use this short gap gently.');
    }
    add(te, te+20, 'Dinner / rest', 'Eat and reset after tuition.');
    final night = te + 20;
    if (b - night >= 120) {
      add(night, night+15, 'Plan & warm-up', 'Pick one clear goal and review class notes.');
      final studyStart = night+15, studyEnd = b-20, mid = studyStart + ((studyEnd-studyStart)*0.55).round();
      add(studyStart, mid, 'Deep study', 'Maths/Science problems or your hardest subject.');
      add(mid, studyEnd, 'Practice & active recall', 'NCERT questions, answer writing and error-log revision.');
      add(b-20, b, 'Prepare for tomorrow', 'Pack your bag and wind down.');
    } else if (b-night >= 30) {
      add(night, b-15, 'Focused revision', 'One small topic or a few exam questions.');
      add(b-15, b, 'Wind down', 'Prepare your bag and get ready for sleep.');
    }
    items.sort((a,b) => int.parse(a['_start']!).compareTo(int.parse(b['_start']!)));
    return items;
  }

  void _startTimer() {
    if (timerRunning) {
      timer?.cancel(); setState(() => timerRunning = false); return;
    }
    if (secondsLeft <= 0) secondsLeft = focusMinutes * 60;
    setState(() => timerRunning = true);
    timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (secondsLeft <= 1) {
        t.cancel();
        setState(() { secondsLeft = 0; timerRunning = false; completedSessions++; });
        await prefs.setInt('completedSessions', completedSessions);
        if (mounted) _message('Focus session complete! Take a short break.');
      } else {
        setState(() => secondsLeft--);
      }
    });
  }

  void _message(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _sectionTitle(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5), Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.65))),
    ]),
  );
  Widget _panel(Widget child) => Card(child: Padding(padding: const EdgeInsets.all(16), child: child));
  Widget _timeField(String label, TextEditingController c) => TextField(
    controller: c, keyboardType: TextInputType.datetime, decoration: InputDecoration(labelText: label, hintText: 'HH:MM'),
    onChanged: (_) { setState(() {}); _saveHours(); },
  );
  Widget _routineView() {
    final items = _routine();
    return Column(children: items.map((e) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _panel(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 92, padding: const EdgeInsets.only(top: 3), child: Text(e['time']!, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB7AEFF)))),
        const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e['title']!, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4), Text(e['desc']!, style: TextStyle(color: Colors.white.withOpacity(.65))),
        ])),
      ])),
    )).toList());
  }

  Widget _dashboard() => ListView(padding: const EdgeInsets.all(16), children: [
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('STUDYOS', style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w900, color: Color(0xFFB7AEFF))),
      const SizedBox(height: 8), const Text('Small steps. Strong results.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8), const Text('Offline-first study planner for your school day, tuition and board exams.'),
      const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: [
        _pill(Icons.check_circle_outline, '$completedSessions focus sessions'),
        _pill(Icons.wifi_off, 'Works offline'),
      ]),
    ])),
    const SizedBox(height: 16),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Today’s focus', 'Choose one clear, achievable target.'),
      TextField(controller: goalController, maxLines: 2, decoration: const InputDecoration(labelText: 'Study goal')),
      const SizedBox(height: 10), FilledButton.icon(onPressed: () async { goal = goalController.text.trim(); await prefs.setString('goal', goal); _message('Goal saved on this device.'); }, icon: const Icon(Icons.save_outlined), label: const Text('Save goal')),
    ])),
    const SizedBox(height: 16),
    _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Quick start', 'Jump straight into the next useful action.'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(onPressed: () => setState(() => tab = 1), icon: const Icon(Icons.calendar_month), label: const Text('Build routine')),
        FilledButton.tonalIcon(onPressed: () => setState(() => tab = 2), icon: const Icon(Icons.timer_outlined), label: const Text('Focus timer')),
        FilledButton.tonalIcon(onPressed: () => setState(() => tab = 3), icon: const Icon(Icons.note_alt_outlined), label: const Text('Exam notes')),
      ]),
    ])),
  ]);

  Widget _pill(IconData icon, String label) => Chip(avatar: Icon(icon, size: 17), label: Text(label));

  Widget _routinePage() => ListView(padding: const EdgeInsets.all(16), children: [
    _sectionTitle('Smart routine planner', 'Change a time and your suggested routine updates automatically.'),
    _panel(Column(children: [
      Row(children: [Expanded(child: _timeField('School starts', schoolStart)), const SizedBox(width: 10), Expanded(child: _timeField('School ends', schoolEnd))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _timeField('Tuition starts', tuitionStart)), const SizedBox(width: 10), Expanded(child: _timeField('Tuition ends', tuitionEnd))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: _timeField('Wake-up time', wake)), const SizedBox(width: 10), Expanded(child: _timeField('Bedtime', bedtime))]),
      const SizedBox(height: 10),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () {
        setState(() {schoolStart.text='06:00'; schoolEnd.text='14:30'; tuitionStart.text='18:00'; tuitionEnd.text='19:00'; wake.text='05:15'; bedtime.text='22:00';});
        _saveHours();
      }, icon: const Icon(Icons.restart_alt), label: const Text('Reset example hours'))),
    ])),
    const SizedBox(height: 14),
    _sectionTitle('Your adjusted day', 'Protect breaks and sleep; change times again whenever needed.'),
    _routineView(),
  ]);

  Widget _focusPage() => ListView(padding: const EdgeInsets.all(16), children: [
    _sectionTitle('Focus mode', 'One task. One session. Put other distractions away.'),
    _panel(Column(children: [
      Text(goal.isEmpty ? 'Choose a goal on the home screen.' : goal, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 20),
      Text('${(secondsLeft ~/ 60).toString().padLeft(2,'0')}:${(secondsLeft % 60).toString().padLeft(2,'0')}', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, letterSpacing: 2)),
      const SizedBox(height: 18),
      Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
        FilledButton.icon(onPressed: _startTimer, icon: Icon(timerRunning ? Icons.pause : Icons.play_arrow), label: Text(timerRunning ? 'Pause' : 'Start 25 min')),
        OutlinedButton.icon(onPressed: () { timer?.cancel(); setState(() {timerRunning=false; secondsLeft=focusMinutes*60;}); }, icon: const Icon(Icons.restart_alt), label: const Text('Reset')),
      ]),
      const SizedBox(height: 12), Text('Completed sessions: $completedSessions', style: TextStyle(color: Colors.white.withOpacity(.65))),
      const SizedBox(height: 10), const Text('The timer runs inside the app. For fewer distractions, enable Do Not Disturb on your device.', textAlign: TextAlign.center),
    ])),
  ]);

  Widget _notesPage() => ListView(padding: const EdgeInsets.all(16), children: [
    _sectionTitle('Exam notes', 'Save formulas, definitions, key points and doubts locally.'),
    _panel(Column(children: [
      DropdownButtonFormField<String>(value: noteSubject, decoration: const InputDecoration(labelText: 'Subject'), items: const [
        'Mathematics','Science','Social Science','English','Hindi','Information Technology (402)','Other'
      ].map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(), onChanged: (v)=>setState(()=>noteSubject=v??'Mathematics')),
      const SizedBox(height: 10), TextField(controller: noteTitle, decoration: const InputDecoration(labelText: 'Note title')),
      const SizedBox(height: 10), TextField(controller: noteBody, minLines: 3, maxLines: 7, decoration: const InputDecoration(labelText: 'Note / formula / question')),
      const SizedBox(height: 10), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () async {
        if (noteTitle.text.trim().isEmpty || noteBody.text.trim().isEmpty) { _message('Add a title and note text first.'); return; }
        setState(() { notes.insert(0, StudyNote(noteSubject, noteTitle.text.trim(), noteBody.text.trim())); noteTitle.clear(); noteBody.clear(); });
        await _saveNotes(); _message('Note saved on this device.');
      }, icon: const Icon(Icons.save), label: const Text('Save note'))),
    ])),
    const SizedBox(height: 14),
    if (notes.isEmpty) _panel(const Text('No saved notes yet. Add your first revision note above.')),
    ...notes.asMap().entries.map((entry) => Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.value.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            Text(entry.value.subject, style: const TextStyle(color: Color(0xFFB7AEFF))),
          ])),
          IconButton(onPressed: () async { setState(() => notes.removeAt(entry.key)); await _saveNotes(); }, icon: const Icon(Icons.delete_outline), tooltip: 'Delete note'),
        ]),
        const SizedBox(height: 8), SelectableText(entry.value.body),
      ])),
    )),
  ]);

  Widget _videosPage() {
    final links = [
      ['CBSE official website', 'Official circulars, syllabus and exam information', 'https://www.cbse.gov.in/'],
      ['NCERT textbooks', 'Use your prescribed textbook as your main source', 'https://ncert.nic.in/textbook.php'],
      ['Class 10 Maths revision', 'Chapter-wise lessons and worked examples', 'https://www.youtube.com/results?search_query=CBSE+Class+10+Maths+NCERT+chapter+wise+revision'],
      ['Class 10 Science revision', 'Concepts, diagrams, numericals and NCERT questions', 'https://www.youtube.com/results?search_query=CBSE+Class+10+Science+NCERT+chapter+wise+revision'],
      ['Social Science revision', 'History, Geography, Civics and Economics', 'https://www.youtube.com/results?search_query=CBSE+Class+10+Social+Science+NCERT+revision'],
      ['English & Hindi revision', 'Literature, writing formats and grammar', 'https://www.youtube.com/results?search_query=CBSE+Class+10+English+Hindi+board+exam+revision'],
      ['Information Technology (402)', 'Employability skills and subject revision', 'https://www.youtube.com/results?search_query=CBSE+Class+10+Information+Technology+402+revision'],
      ['Solved sample papers', 'Practise under timed conditions and review marking schemes', 'https://www.youtube.com/results?search_query=CBSE+Class+10+sample+paper+solved+with+marking+scheme'],
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      _sectionTitle('Board exam resources', 'These links open when you have internet access.'),
      _panel(const Text('The planner and notes work offline. Streaming videos require internet, and links may open the appropriate installed app or a web page. Follow your current CBSE syllabus and school instructions.')),
      const SizedBox(height: 12),
      ...links.map((e) => Padding(padding: const EdgeInsets.only(bottom: 9), child: _panel(Row(children: [
        const Icon(Icons.play_circle_outline, color: Color(0xFFB7AEFF), size: 30), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e[0], style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4), Text(e[1], style: TextStyle(color: Colors.white.withOpacity(.65))),
        ])),
        IconButton(onPressed: () async { final uri = Uri.parse(e[2]); if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) _message('Could not open this link.'); }, icon: const Icon(Icons.open_in_new)),
      ])))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final pages = [_dashboard(), _routinePage(), _focusPage(), _notesPage(), _videosPage()];
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final nav = NavigationRail(
      selectedIndex: tab, onDestinationSelected: (v)=>setState(()=>tab=v),
      labelType: NavigationRailLabelType.all, backgroundColor: const Color(0xFF151724),
      destinations: const [
        NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Home')),
        NavigationRailDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: Text('Routine')),
        NavigationRailDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: Text('Focus')),
        NavigationRailDestination(icon: Icon(Icons.note_alt_outlined), selectedIcon: Icon(Icons.note_alt), label: Text('Notes')),
        NavigationRailDestination(icon: Icon(Icons.ondemand_video_outlined), selectedIcon: Icon(Icons.ondemand_video), label: Text('Videos')),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('StudyOS'), actions: const [Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Center(child: Icon(Icons.wifi_off))) ]),
      body: wide ? Row(children: [nav, const VerticalDivider(width: 1), Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: pages[tab])))]) : pages[tab],
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: tab, onDestinationSelected: (v)=>setState(()=>tab=v), destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Routine'),
        NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Focus'),
        NavigationDestination(icon: Icon(Icons.note_alt_outlined), label: 'Notes'),
        NavigationDestination(icon: Icon(Icons.ondemand_video_outlined), label: 'Videos'),
      ]),
    );
  }
}
