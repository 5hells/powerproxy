import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'dart:ui' show TextDirection;
import 'dart:async';
import 'package:wear_plus/wear_plus.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:arc_text/arc_text.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => ScheduleProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerSchool Schedule',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xFF1E1E1E),
          background: const Color(0xFF121212),
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: const Color(0xFF2A2A2A),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
        ),
      ),
      home: const AuthCheckScreen(),
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkCredentials();
  }

  Future<void> _checkCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username')?.trim();
    final password = prefs.getString('password')?.trim();
    
    if (mounted) {
      if (username != null && password != null && username.isNotEmpty && password.isNotEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ScheduleScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class ScheduleProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _schedule = [];
  Map<String, dynamic>? _attendanceData;
  Map<String, dynamic>? _classGrades;
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get schedule => _schedule;
  Map<String, dynamic>? get attendanceData => _attendanceData;
  Map<String, dynamic>? get classGrades => _classGrades;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSchedule() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    int retryCount = 0;
    const maxRetries = 10; // Allow more retries
    const initialDelay = Duration(seconds: 2);

    while (retryCount < maxRetries) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username');
        final password = prefs.getString('password');
        final psBase = prefs.getString('ps_base') ?? 'holyghostprep';
        final apiUrl = prefs.getString('api_url') ?? 'http://192.168.1.100:3000';

        if (username == null || password == null || username.isEmpty || password.isEmpty) {
          throw Exception('Please set credentials in settings');
        }

        // Authenticate
        final authResponse = await http.post(
          Uri.parse('$apiUrl/authenticate'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'username': username,
            'password': password,
            'ps-base': psBase,
          },
        );

        if (authResponse.statusCode != 200) {
          throw Exception('Authentication failed');
        }

        final cookies = json.decode(utf8.decode(authResponse.bodyBytes));

        // Get schedule
        final scheduleResponse = await http.post(
          Uri.parse('$apiUrl/schedule'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'cookies-json': json.encode(cookies),
            'ps-base': psBase,
          },
        );

        if (scheduleResponse.statusCode == 200) {
          _schedule = List<Map<String, dynamic>>.from(json.decode(utf8.decode(scheduleResponse.bodyBytes)));
        }

        // Get attendance/grades
        final gradesResponse = await http.post(
          Uri.parse('$apiUrl/grades'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'cookies-json': json.encode(cookies),
            'ps-base': psBase,
          },
        );

        if (gradesResponse.statusCode == 200) {
          _attendanceData = json.decode(utf8.decode(gradesResponse.bodyBytes));
        }

        // Get per-class grades
        final classGradesResponse = await http.post(
          Uri.parse('$apiUrl/class-grades'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'cookies-json': json.encode(cookies),
            'ps-base': psBase,
          },
        );

        if (classGradesResponse.statusCode == 200) {
          _classGrades = json.decode(utf8.decode(classGradesResponse.bodyBytes));
        }

        // Success
        _isLoading = false;
        notifyListeners();
        return;

      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          _error = 'Failed to load schedule after $maxRetries attempts: ${e.toString()}';
          _isLoading = false;
          notifyListeners();
          return;
        }
        // Exponential back-off
        final delay = initialDelay * (1 << (retryCount - 1));
        await Future.delayed(delay);
      }
    }
  }
}

class WearScaffold extends StatelessWidget {
  final Widget body;

  const WearScaffold({super.key, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: body,
      ),
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScheduleProvider>().loadSchedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WearScaffold(
      body: Consumer<ScheduleProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${provider.error}',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.loadSchedule(),
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    ),
                    child: const Text('Settings'),
                  ),
                ],
              ),
            );
          }

          return SectographSchedule(
            schedule: provider.schedule,
            attendanceData: provider.attendanceData,
          );
        },
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _psBaseController = TextEditingController(text: 'holyghostprep');
  final _apiUrlController = TextEditingController(text: 'http://192.168.1.100:3000');

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _usernameController.text = (prefs.getString('username') ?? '').trim();
      _passwordController.text = (prefs.getString('password') ?? '').trim();
      _psBaseController.text = (prefs.getString('ps_base') ?? 'holyghostprep').trim();
      _apiUrlController.text = (prefs.getString('api_url') ?? 'http://10.0.2.2:3000').trim();
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final psBase = _psBaseController.text.trim();
    final apiUrl = _apiUrlController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username and password are required')),
      );
      return;
    }

    await prefs.setString('username', username);
    await prefs.setString('password', password);
    await prefs.setString('ps_base', psBase.isEmpty ? 'holyghostprep' : psBase);
    await prefs.setString('api_url', apiUrl.isEmpty ? 'http://192.168.1.100:3000' : apiUrl);
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ScheduleScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WearScaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'PowerSchool Login',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter your credentials to sync your schedule',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'Enter your PowerSchool username',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your PowerSchool password',
              ),
              obscureText: true,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _psBaseController,
              decoration: const InputDecoration(
                labelText: 'PowerSchool Base',
                hintText: 'e.g., yourschool',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API URL',
                hintText: 'Server address',
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Login & Sync',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _psBaseController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }
}

class SectographSchedule extends StatefulWidget {
  final List<Map<String, dynamic>> schedule;
  final Map<String, dynamic>? attendanceData;

  const SectographSchedule({
    super.key,
    required this.schedule,
    this.attendanceData,
  });

  @override
  State<SectographSchedule> createState() => _SectographScheduleState();
}

class _SectographScheduleState extends State<SectographSchedule>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late AnimationController _transitionController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _titleFadeAnimation;
  int _currentIndex = 0;
  Map<String, dynamic>? _currentClass;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _transitionController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _transitionController, curve: Curves.easeInOut),
    );
    _titleFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _transitionController, curve: Curves.easeInOut),
    );
    _updateTodayIndex();
    _animationController.forward();
    _transitionController.value = 1.0; // Start at full scale and opacity
    _updateCurrentClass();
    // Update current class every minute
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        _updateCurrentClass();
      }
    });
    // Update hand position every second
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(SectographSchedule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schedule != widget.schedule) {
      _updateCurrentClass();
      _updateTodayIndex();
    }
  }

  void _updateTodayIndex() {
    final now = DateTime.now();
    final today = _getTodayString(now);
    _currentIndex = widget.schedule.indexWhere((day) => day['name'] == today);
    if (_currentIndex == -1) _currentIndex = 0;
  }

  void _updateCurrentClass() {
    final now = DateTime.now();
    final today = _getTodayString(now);
    final todayDay = widget.schedule.firstWhere(
      (day) => day['name'] == today,
      orElse: () => <String, dynamic>{},
    );
    final List<Map<String, dynamic>> todaySchedule = todayDay.isNotEmpty ? List<Map<String, dynamic>>.from(todayDay['classes'] as List<dynamic>) : [];

    _currentClass = _getCurrentClass(todaySchedule, now);
    _sendCurrentClassToComplication();
  }

  Future<void> _sendCurrentClassToComplication() async {
    try {
      const platform = MethodChannel('com.example.wearos/complication');
      await platform.invokeMethod('updateCurrentClass', {
        'name': _currentClass?['name'] ?? 'No Class',
        'room': _currentClass?['room'] ?? 'N/A',
      });
    } catch (e) {
      // Ignore errors
    }
  }

  Map<String, dynamic>? _getCurrentClass(List<Map<String, dynamic>> todaySchedule, DateTime now) {
    for (final classData in todaySchedule) {
      final startStr = classData['start'] as String?;
      final endStr = classData['end'] as String?;
      if (startStr != null && endStr != null) {
        final start = _parseTime(startStr);
        final end = _parseTime(endStr);
        if (start != null && end != null) {
          final startDateTime = DateTime(now.year, now.month, now.day, start.hour, start.minute);
          final endDateTime = DateTime(now.year, now.month, now.day, end.hour, end.minute);
          if (now.isAfter(startDateTime) && now.isBefore(endDateTime)) {
            return classData;
          }
        }
      }
    }
    return null;
  }

  List<DateTime>? _parseTimeRange(String timeStr) {
    final parts = timeStr.split(' - ');
    if (parts.length == 2) {
      try {
        final start = _parseTime(parts[0]);
        final end = _parseTime(parts[1]);
        if (start != null && end != null) {
          final now = DateTime.now();
          return [
            DateTime(now.year, now.month, now.day, start.hour, start.minute),
            DateTime(now.year, now.month, now.day, end.hour, end.minute),
          ];
        }
      } catch (e) {
        // Ignore parsing errors
      }
    }
    return null;
  }

  DateTime? _parseTime(String timeStr) {
    final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)');
    final match = regex.firstMatch(timeStr.trim());
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final isPM = match.group(3) == 'PM';
      final adjustedHour = isPM && hour != 12 ? hour + 12 : (hour == 12 && !isPM ? 0 : hour);
      return DateTime(0, 1, 1, adjustedHour, minute);
    }
    return null;
  }

  void _changeDay(int newIndex) {
    _transitionController.animateTo(0.0, duration: const Duration(milliseconds: 150)).then((_) {
      setState(() {
        _currentIndex = newIndex;
      });
      _transitionController.animateTo(1.0, duration: const Duration(milliseconds: 150));
    });
  }

  @override
  Widget build(BuildContext context) {
    final classes = List<Map<String, dynamic>>.from(widget.schedule[_currentIndex]['classes'] as List<dynamic>);
    DateTime? minStart;
    DateTime? maxEnd;
    for (final classData in classes) {
      final start = _parseTime(classData['start'] as String);
      final end = _parseTime(classData['end'] as String);
      if (start != null && end != null) {
        if (minStart == null || start.isBefore(minStart)) minStart = start;
        if (maxEnd == null || end.isAfter(maxEnd)) maxEnd = end;
      }
    }

    return WearScaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity! > 0) {
                  // Swipe right, previous day
                  final newIndex = (_currentIndex - 1 + widget.schedule.length) % widget.schedule.length;
                  _changeDay(newIndex);
                } else if (details.primaryVelocity! < 0) {
                  // Swipe left, next day
                  final newIndex = (_currentIndex + 1) % widget.schedule.length;
                  _changeDay(newIndex);
                }
              },
              onTap: () {
                final day = widget.schedule[_currentIndex];
                final dayName = day['name'] as String;
                final isToday = _currentIndex == _todayIndex;

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => TodayScheduleScreen(
                      schedule: classes,
                      title: isToday ? 'Today\'s Schedule' : '$dayName\'s Schedule',
                      attendanceData: widget.attendanceData,
                    ),
                  ),
                );
              },
              onLongPress: () {
                final day = widget.schedule[_currentIndex];

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => GradeBookScreen(
                      schedule: classes,
                      attendanceData: widget.attendanceData,
                      classGrades: context.read<ScheduleProvider>().classGrades!,
                    ),
                  ),
                );
              },
              child: Stack(
                children: [
                  // Circular schedule display
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: DaySchedulePainter(
                        classes: classes,
                        currentClass: _currentIndex == _todayIndex ? _currentClass : null,
                        minStart: minStart,
                        maxEnd: maxEnd,
                      ),
                    ),
                  ),

                  // Current time indicator (only for today)
                  if (_currentIndex == _todayIndex)
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: TimeIndicatorPainter(
                          minStart: minStart,
                          maxEnd: maxEnd,
                        ),
                      ),
                    ),

                  // Center display
                  Center(
                    child: FadeTransition(
                      opacity: _titleFadeAnimation,
                      child: _currentIndex == _todayIndex
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_currentClass != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.blue.withOpacity(0.5)),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          _currentClass!['name'] ?? 'Unknown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        Text(
                                          _currentClass!['room'] ?? 'N/A',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Column(
                                    children: [
                                      Text(
                                        widget.schedule[_currentIndex]['name'] as String,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold
                                        )
                                      ),
                                      Text(
                                        "Today",
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w300
                                        )
                                      )
                                    ]
                                  )
                                ]
                              ],
                            )
                          : Text(
                              widget.schedule[_currentIndex]['name'] as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Time display at bottom
          Positioned(
            bottom: 2,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                DateFormat.jm().format(DateTime.now()),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int get _todayIndex {
    final now = DateTime.now();
    final today = _getTodayString(now);
    return widget.schedule.indexWhere((day) => day['name'] == today);
  }

  String _getTodayString(DateTime now) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[now.weekday - 1];
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transitionController.dispose();
    super.dispose();
  }
}

class DaySchedulePainter extends CustomPainter {
  final List<Map<String, dynamic>> classes;
  final Map<String, dynamic>? currentClass;
  final DateTime? minStart;
  final DateTime? maxEnd;

  DaySchedulePainter({required this.classes, this.currentClass, this.minStart, this.maxEnd});

  String _getTodayString(DateTime now) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[now.weekday - 1];
  }

  DateTime? _parseTime(String timeStr) {
    final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)');
    final match = regex.firstMatch(timeStr.trim());
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final isPM = match.group(3) == 'PM';
      final adjustedHour = isPM && hour != 12 ? hour + 12 : (hour == 12 && !isPM ? 0 : hour);
      return DateTime(0, 1, 1, adjustedHour, minute);
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Draw background circle
    final bgPaint = Paint()
      ..color = Colors.grey.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, bgPaint);

    if (classes.isEmpty) return;

    // Calculate school day range
    DateTime? schoolMinStart = minStart;
    DateTime? schoolMaxEnd = maxEnd;
    if (schoolMinStart == null || schoolMaxEnd == null) {
      // Fallback to 24h if not provided
      schoolMinStart = DateTime(0, 1, 1, 0, 0);
      schoolMaxEnd = DateTime(0, 1, 1, 23, 59);
    }
    final totalMinutes = schoolMaxEnd.difference(schoolMinStart).inMinutes.toDouble();

    // Sort by start time
    final sortedClasses = List<Map<String, dynamic>>.from(classes);
    sortedClasses.sort((a, b) {
      final aStart = _parseTime(a['start'] as String? ?? '');
      final bStart = _parseTime(b['start'] as String? ?? '');
      if (aStart == null || bStart == null) return 0;
      return aStart.compareTo(bStart);
    });

    // Draw class sectors
    _drawClasses(canvas, center, radius, sortedClasses, schoolMinStart, totalMinutes);

    // Draw center circle to make sectors appear as arcs
    final centerCircleRadius = 40.0;
    final centerPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, centerCircleRadius, centerPaint);
  }

  void _drawClasses(Canvas canvas, Offset center, double radius, List<Map<String, dynamic>> sortedClasses, DateTime schoolMinStart, double totalMinutes) {
    const fullCircle = 2 * pi;

    for (final classData in sortedClasses) {
      final startStr = classData['start'] as String?;
      final endStr = classData['end'] as String?;
      if (startStr == null || endStr == null) continue;

      final startTime = _parseTime(startStr);
      final endTime = _parseTime(endStr);
      if (startTime == null || endTime == null) continue;

      final startMinutes = startTime.difference(schoolMinStart).inMinutes.toDouble();
      final endMinutes = endTime.difference(schoolMinStart).inMinutes.toDouble();

      if (startMinutes < 0 || endMinutes > totalMinutes) continue; // Skip classes outside school day

      final startAngle = (startMinutes / totalMinutes) * fullCircle - pi / 2;
      final sweepAngle = ((endMinutes - startMinutes) / totalMinutes) * fullCircle * 0.95; // Leave small gap

      final className = classData['name'] as String? ?? 'Unknown';
      final isCurrent = currentClass != null && classData['name'] == currentClass!['name'] && classData['start'] == currentClass!['start'];

      // Generate rainbow color based on start angle
      final normalizedAngle = (startAngle + pi / 2) % (2 * pi);
      final hue = (normalizedAngle / (2 * pi)) * 360;
      final baseColor = HSVColor.fromAHSV(1.0, hue, isCurrent ? 1.0 : 0.8, isCurrent ? 1.0 : 0.9).toColor();

      final classPaint = Paint()
        ..color = baseColor
        ..style = PaintingStyle.fill;

      // Draw class sector
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        classPaint,
      );

      // Draw class label
      final labelAngle = startAngle + sweepAngle / 2;
      final labelRadius = radius - 25;
      final labelX = center.dx + labelRadius * cos(labelAngle);
      final labelY = center.dy + labelRadius * sin(labelAngle);

      final room = classData['room'] as String? ?? 'N/A';
      final displayName = _abbreviateClassName(className);
      final displayRoom = _abbreviateRoom(room);

      // Choose text color based on background luminance for contrast
      final textColor = baseColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
      final roomTextColor = textColor.withOpacity(0.7);

      final textPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: displayName,
              style: TextStyle(
                color: textColor,
                fontSize: 8,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            TextSpan(text: '\n'),
            TextSpan(
              text: displayRoom,
              style: TextStyle(
                color: roomTextColor,
                fontSize: 7,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w400,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(labelX - textPainter.width / 2, labelY - textPainter.height / 2),
      );
    }
  }

  String _abbreviateClassName(String name) {
    if (name.length <= 8) return name;
    return '${name.substring(0, 6)}..';
  }

  String _abbreviateRoom(String room) {
    if (room.length <= 4) return room;
    return '${room.substring(0, 3)}.';
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TimeIndicatorPainter extends CustomPainter {
  final DateTime? minStart;
  final DateTime? maxEnd;

  TimeIndicatorPainter({this.minStart, this.maxEnd});

  @override
  void paint(Canvas canvas, Size size) {
    if (minStart == null || maxEnd == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final now = DateTime.now();
    
    // Create a DateTime object with just the time components for comparison
    final currentTime = DateTime(0, 1, 1, now.hour, now.minute, now.second);
    
    final totalMinutes = maxEnd!.difference(minStart!).inMinutes.toDouble();
    final currentMinutes = currentTime.difference(minStart!).inMinutes.toDouble();

    if (currentMinutes < 0 || currentMinutes > totalMinutes) return; // Don't draw if outside school day

    // Calculate angle based on current time within school day
    final angle = (currentMinutes / totalMinutes) * 2 * pi - pi / 2;
    final radius = size.width / 2 - 20; // Match the sector radius
    final centerCircleRadius = 40.0;

    final endPoint = Offset(
      center.dx + radius * cos(angle),
      center.dy + radius * sin(angle),
    );

    // Start point from edge of center circle
    final startPoint = Offset(
      center.dx + centerCircleRadius * cos(angle),
      center.dy + centerCircleRadius * sin(angle),
    );

    // Draw hand shadow first
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(startPoint, endPoint, shadowPaint);

    // Draw the clock hand as a line
    final handPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(startPoint, endPoint, handPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TimeRemainingPainter extends CustomPainter {
  final Map<String, dynamic>? currentClass;
  final DateTime? minStart;
  final DateTime? maxEnd;

  TimeRemainingPainter({this.currentClass, this.minStart, this.maxEnd});

  DateTime? _parseTime(String timeStr) {
    final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)');
    final match = regex.firstMatch(timeStr.trim());
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final isPM = match.group(3) == 'PM';
      final adjustedHour = isPM && hour != 12 ? hour + 12 : (hour == 12 && !isPM ? 0 : hour);
      return DateTime(0, 1, 1, adjustedHour, minute);
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (currentClass == null || minStart == null || maxEnd == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    final now = DateTime.now();

    // Parse class end time
    final endStr = currentClass!['end'] as String?;
    if (endStr == null) return;

    final endTime = _parseTime(endStr);
    if (endTime == null) return;

    // Calculate remaining time
    final endDateTime = DateTime(now.year, now.month, now.day, endTime.hour, endTime.minute);
    final remaining = endDateTime.difference(now);

    if (remaining.isNegative) return; // Class already ended

    // Format remaining time
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final timeStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    // Calculate angle for class end
    final totalMinutes = maxEnd!.difference(minStart!).inMinutes.toDouble();
    final endMinutes = endTime.difference(minStart!).inMinutes.toDouble();

    final angle = (endMinutes / totalMinutes) * 2 * pi - pi / 2;
    final labelRadius = radius + 25;
    final labelX = center.dx + labelRadius * cos(angle);
    final labelY = center.dy + labelRadius * sin(angle);

    // Draw time remaining label
    final textPainter = TextPainter(
      text: TextSpan(
        text: timeStr,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(labelX - textPainter.width / 2, labelY - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class TodayScheduleScreen extends StatelessWidget {
  final List<Map<String, dynamic>> schedule;
  final String title;
  final Map<String, dynamic>? attendanceData;

  const TodayScheduleScreen({super.key, required this.schedule, this.title = 'Today\'s Schedule', this.attendanceData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: null,
      body: schedule.isEmpty
          ? const Center(
              child: Text(
                'No classes today',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: schedule.length,
              itemBuilder: (context, index) {
                final classData = schedule[index];
                final isCurrent = _isCurrentClass(classData);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                      : Theme.of(context).cardTheme.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: isCurrent
                        ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                        : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                classData['name'] ?? 'Unknown',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isCurrent ? Theme.of(context).colorScheme.primary : Colors.white,
                                ),
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'NOW',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow('Teacher', classData['teacher'] ?? 'N/A'),
                        _buildInfoRow('Room', classData['room'] ?? 'N/A'),
                        _buildInfoRow('Time', '${classData['start'] ?? 'N/A'} - ${classData['end'] ?? 'N/A'}'),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  bool _isCurrentClass(Map<String, dynamic> classData) {
    final now = DateTime.now();
    final startStr = classData['start'] as String?;
    final endStr = classData['end'] as String?;
    if (startStr != null && endStr != null) {
      final start = _parseTime(startStr);
      final end = _parseTime(endStr);
      if (start != null && end != null) {
        final startDateTime = DateTime(now.year, now.month, now.day, start.hour, start.minute);
        final endDateTime = DateTime(now.year, now.month, now.day, end.hour, end.minute);
        return now.isAfter(startDateTime) && now.isBefore(endDateTime);
      }
    }
    return false;
  }

  List<DateTime>? _parseTimeRange(String timeStr) {
    final parts = timeStr.split(' - ');
    if (parts.length == 2) {
      try {
        final start = _parseTime(parts[0]);
        final end = _parseTime(parts[1]);
        if (start != null && end != null) {
          final now = DateTime.now();
          return [
            DateTime(now.year, now.month, now.day, start.hour, start.minute),
            DateTime(now.year, now.month, now.day, end.hour, end.minute),
          ];
        }
      } catch (e) {
        // Ignore parsing errors
      }
    }
    return null;
  }

  DateTime? _parseTime(String timeStr) {
    final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)');
    final match = regex.firstMatch(timeStr.trim());
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final isPM = match.group(3) == 'PM';
      final adjustedHour = isPM && hour != 12 ? hour + 12 : (hour == 12 && !isPM ? 0 : hour);
      return DateTime(0, 1, 1, adjustedHour, minute);
    }
    return null;
  }
}

class GradeBookScreen extends StatelessWidget {
  final List<Map<String, dynamic>> schedule;
  final Map<String, dynamic>? attendanceData;
  final Map<String, dynamic> classGrades;

  const GradeBookScreen({super.key, required this.schedule, this.attendanceData, required this.classGrades});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: schedule.isEmpty
          ? const Center(
              child: Text(
                'No classes',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: schedule.length,
              itemBuilder: (context, index) {
                final classData = schedule[index];
                final className = classData['name'] as String? ?? 'Unknown';
                final room = classData['room'] as String? ?? 'N/A';
                final teacher = classData['teacher'] as String? ?? 'N/A';
                final startTime = classData['start'] as String? ?? 'N/A';
                final endTime = classData['end'] as String? ?? 'N/A';

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: Theme.of(context).cardTheme.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          className,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDetailRow('Teacher', teacher),
                        _buildDetailRow('Room', room),
                        _buildDetailRow('Time', '$startTime - $endTime'),
                        const SizedBox(height: 10),
                        Text(
                          'Grades & Attendance:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildGradeInfo(className),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeInfo(String className) {
    // Extract grades from classGrades map
    String s2 = 'N/A';
    String p1 = 'N/A';
    String s1 = 'N/A';
    String absences = 'N/A';
    String tardies = 'N/A';

    if (classGrades.isNotEmpty && classGrades.containsKey('classes')) {
      final classesData = classGrades['classes'] as Map<String, dynamic>?;
      if (classesData != null && classesData.containsKey(className)) {
        final gradeData = classesData[className] as Map<String, dynamic>;
        
        s2 = gradeData['s2']?.toString() ?? 'N/A';
        p1 = gradeData['p1']?.toString() ?? 'N/A';
        s1 = gradeData['s1']?.toString() ?? 'N/A';
        absences = gradeData['absences']?.toString() ?? 'N/A';
        tardies = gradeData['tardies']?.toString() ?? 'N/A';
      }
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildGradeChip('S2', s2),
            _buildGradeChip('P1', p1),
            _buildGradeChip('S1', s1),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildAttendanceChip('Absences', absences),
            _buildAttendanceChip('Tardies', tardies),
          ],
        ),
      ],
    );
  }

  Widget _buildGradeChip(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.blue,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceChip(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
