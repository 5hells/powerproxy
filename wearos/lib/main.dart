import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:intl/intl.dart' hide TextDirection;

import 'dart:math' as math;

class TimeParseResult {
  final DateTime? time;
  TimeParseResult(this.time);
}

DateTime? parseTimeSync(String? timeStr) {
  if (timeStr == null || timeStr.isEmpty) return null;
  final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)');
  final match = regex.firstMatch(timeStr.trim());
  if (match != null) {
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final isPM = match.group(3) == 'PM';
    final adjustedHour = isPM && hour != 12
        ? hour + 12
        : (hour == 12 && !isPM ? 0 : hour);
    return DateTime(0, 1, 1, adjustedHour, minute);
  }
  return null;
}


/// A widget that displays text in an arc shape.
class ArcText extends StatelessWidget {
  const ArcText({
    super.key,
    required this.radius,
    required this.text,
    required this.textStyle,
    this.startAngle = 0,
    this.alignment = Alignment.center,
  });

  /// Radius of the arc.
  final double radius;

  /// Text to display in an arc shape.
  final String text;

  /// Starting angle of the text.
  final double startAngle;

  /// Style of the text.
  final TextStyle textStyle;

  /// Alignment for positioning the arc text.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _ArcTextPainter(
        radius,
        text,
        textStyle,
        initialAngle: startAngle,
        alignment: alignment,
      ),
    ),
  );
}

class _ArcTextPainter extends CustomPainter {
  _ArcTextPainter(
    this.radius,
    this.text,
    this.textStyle, {
    this.initialAngle = 0,
    this.alignment = Alignment.center,
  });

  final double radius;
  final String text;
  final double initialAngle;
  final TextStyle textStyle;
  final Alignment alignment;

  final _textPainter = TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate center point based on alignment
    late Offset center;

    if (alignment == Alignment.topCenter) {
      center = Offset(size.width / 2, 50);
    } else if (alignment == Alignment.bottomCenter) {
      center = Offset(size.width / 2, size.height - 50);
    } else {
      center = Offset(size.width / 2, size.height / 2);
    }

    // Translate to center point
    canvas.translate(center.dx, center.dy);

    // Pre-calculate total text angle to center it
    double totalAngle = 0;
    for (int i = 0; i < text.length; i++) {
      _textPainter.text = TextSpan(text: text[i], style: textStyle);
      _textPainter.layout(minWidth: 0, maxWidth: double.maxFinite);
      final d = _textPainter.width;
      final alpha = 2 * math.asin(d / (2 * radius));
      totalAngle += alpha;
    }

    // Center the text on the arc
    double startAngle = initialAngle - totalAngle / 2;

    double angle = startAngle;
    for (int i = 0; i < text.length; i++) {
      angle += _drawLetter(canvas, text[i], angle);
    }
  }

  double _drawLetter(Canvas canvas, String letter, double prevAngle) {
    _textPainter.text = TextSpan(text: letter, style: textStyle);
    _textPainter.layout(minWidth: 0, maxWidth: double.maxFinite);

    final double d = _textPainter.width;
    final double alpha = 2 * math.asin(d / (2 * radius));

    // Rotate to angle and draw
    canvas.rotate(alpha / 2);
    _textPainter.paint(canvas, Offset(0, -radius));
    canvas.rotate(alpha / 2);

    return alpha;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

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
        colorScheme:
            ColorScheme.fromSeed(
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      final password = prefs.getString('password');

      // Wait for next frame to ensure widget is built
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;

      // Check if credentials exist and are not empty after trimming
      final hasValidCredentials = username != null &&
          password != null &&
          username.trim().isNotEmpty &&
          password.trim().isNotEmpty;

      if (hasValidCredentials) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const ScheduleScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      }
    } catch (e) {
      // If any error occurs, go to settings screen
      if (mounted) {
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
      body: const Center(child: CircularProgressIndicator()),
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

  double get gpa {
    if (_classGrades == null || !_classGrades!.containsKey('classes'))
      return 0.0;
    final classes = _classGrades!['classes'] as Map<String, dynamic>;
    double totalPoints = 0.0;
    int count = 0;
    for (final gradeData in classes.values) {
      if (gradeData is Map<String, dynamic>) {
        final grade =
            gradeData['s2'] as String? ??
            gradeData['p1'] as String? ??
            gradeData['s1'] as String?;
        if (grade != null && grade.isNotEmpty) {
          final points = _letterToGpa(grade);
          if (points != null) {
            totalPoints += points;
            count++;
          }
        }
      }
    }
    return count > 0 ? totalPoints / count : 0.0;
  }

  static double? _letterToGpa(String grade) {
    final cleanGrade = grade.toUpperCase().trim();
    switch (cleanGrade) {
      case 'A+':
      case 'A':
        return 4.0;
      case 'A-':
        return 3.67;
      case 'B+':
        return 3.33;
      case 'B':
        return 3.0;
      case 'B-':
        return 2.67;
      case 'C+':
        return 2.33;
      case 'C':
        return 2.0;
      case 'C-':
        return 1.67;
      case 'D+':
        return 1.33;
      case 'D':
        return 1.0;
      case 'F':
        return 0.0;
      default:
        return null;
    }
  }

  Future<void> loadSchedule() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Load from cache
    await _loadFromCache();

    // If we have cached data, stop showing loading immediately
    if (_schedule.isNotEmpty) {
      _isLoading = false;
      notifyListeners();
    }

    // Then load from network in background
    _loadFromNetwork();
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final scheduleJson = prefs.getString('cached_schedule');
    final attendanceJson = prefs.getString('cached_attendance');
    final gradesJson = prefs.getString('cached_grades');

    if (scheduleJson != null) {
      try {
        _schedule = List<Map<String, dynamic>>.from(json.decode(scheduleJson));
      } catch (e) {
        // Ignore invalid cache
      }
    }

    if (attendanceJson != null) {
      try {
        _attendanceData = json.decode(attendanceJson);
      } catch (e) {
        // Ignore
      }
    }

    if (gradesJson != null) {
      try {
        _classGrades = json.decode(gradesJson);
      } catch (e) {
        // Ignore
      }
    }

    notifyListeners();
  }

  Future<void> _loadFromNetwork() async {
    int retryCount = 0;
    const maxRetries = 3;
    const initialDelay = Duration(seconds: 1);

    // Add overall timeout to prevent hanging indefinitely
    try {
      await _loadFromNetworkWithRetry(retryCount, maxRetries, initialDelay)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      _error = 'Network request timed out. Using cached data.';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadFromNetworkWithRetry(
    int retryCount,
    int maxRetries,
    Duration initialDelay,
  ) async {
    while (retryCount < maxRetries) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final username = prefs.getString('username')?.trim();
        final password = prefs.getString('password')?.trim();
        final psBase = prefs.getString('ps_base')?.trim() ?? 'holyghostprep';
        final apiUrl =
            prefs.getString('api_url')?.trim() ?? 'http://192.168.1.100:3000';

        if (username == null ||
            password == null ||
            username.isEmpty ||
            password.isEmpty) {
          _error = 'Please set credentials in settings';
          _isLoading = false;
          notifyListeners();
          return;
        }

        // Authenticate
        final authResponse = await http.post(
          Uri.parse('$apiUrl/authenticate'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'username': username, 'password': password, 'ps-base': psBase},
        ).timeout(const Duration(seconds: 30));

        if (authResponse.statusCode != 200) {
          if (authResponse.statusCode == 401 || authResponse.statusCode == 403) {
            throw Exception('Invalid credentials. Please check your username and password.');
          }
          throw Exception('Authentication failed with status ${authResponse.statusCode}');
        }

        final cookies = json.decode(utf8.decode(authResponse.bodyBytes));

        // Get schedule, grades, and class-grades in parallel
        final scheduleFuture = http.post(
          Uri.parse('$apiUrl/schedule'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'cookies-json': json.encode(cookies), 'ps-base': psBase},
        ).timeout(const Duration(seconds: 5));
        final gradesFuture = http.post(
          Uri.parse('$apiUrl/grades'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'cookies-json': json.encode(cookies), 'ps-base': psBase},
        ).timeout(const Duration(seconds: 5));
        final classGradesFuture = http.post(
          Uri.parse('$apiUrl/class-grades'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'cookies-json': json.encode(cookies), 'ps-base': psBase},
        ).timeout(const Duration(seconds: 5));

        final responses = await Future.wait([scheduleFuture, gradesFuture, classGradesFuture]);

        if (responses[0].statusCode == 200) {
          _schedule = List<Map<String, dynamic>>.from(
            json.decode(utf8.decode(responses[0].bodyBytes)),
          );
          // Cache it
          await prefs.setString('cached_schedule', json.encode(_schedule));
        }

        if (responses[1].statusCode == 200) {
          _attendanceData = json.decode(utf8.decode(responses[1].bodyBytes));
          await prefs.setString(
            'cached_attendance',
            json.encode(_attendanceData),
          );
        }

        if (responses[2].statusCode == 200) {
          _classGrades = json.decode(
            utf8.decode(responses[2].bodyBytes),
          );
          await prefs.setString('cached_grades', json.encode(_classGrades));
        }

        // Success
        _isLoading = false;
        notifyListeners();
        return;
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          _error =
              'Failed to load schedule after $maxRetries attempts: ${e.toString()}';
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
      body: SafeArea(child: body),
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
            return const Center(child: CircularProgressIndicator());
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
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    ),
                    child: const Text('Settings'),
                  ),
                ],
              ),
            );
          }

          if (provider.schedule.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today, size: 48, color: Colors.white70),
                  const SizedBox(height: 16),
                  const Text(
                    'No schedule available',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pull down to refresh',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    ),
                    child: const Text('Check Settings'),
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
  final _apiUrlController = TextEditingController(
    text: 'http://192.168.1.100:3000',
  );

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _usernameController.text = prefs.getString('username')?.trim() ?? '';
          _passwordController.text = prefs.getString('password')?.trim() ?? '';
          _psBaseController.text = prefs.getString('ps_base')?.trim() ?? 'holyghostprep';
          _apiUrlController.text = prefs.getString('api_url')?.trim() ?? 'http://192.168.1.100:3000';
        });
      }
    } catch (e) {
      // Silently fail and use defaults if loading fails
    }
  }

  Future<void> _saveSettings() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final psBase = _psBaseController.text.trim();
    final apiUrl = _apiUrlController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Username and password are required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', username);
      await prefs.setString('password', password);
      await prefs.setString('ps_base', psBase.isEmpty ? 'holyghostprep' : psBase);
      await prefs.setString(
        'api_url',
        apiUrl.isEmpty ? 'http://192.168.1.100:3000' : apiUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
        
        // Wait for snackbar to show before navigating
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ScheduleScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
              style: TextStyle(color: Colors.white70, fontSize: 14),
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
  late AnimationController _transitionController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _titleFadeAnimation;
  late AnimationController _titleScaleController;
  late Animation<double> _titleScaleAnimation;
  int _currentIndex = 0;
  Map<String, dynamic>? _currentClass;
  bool _isOverview = false;
  late AnimationController _overviewController;
  late Animation<double> _overviewScale;
  late Animation<double> _overviewFade;
  late AnimationController _rotationController;

  // Cached display data to prevent ANR from repeated calculations
  List<Map<String, dynamic>> _cachedDisplayClasses = [];
  DateTime _cachedMinStart = DateTime(0, 1, 1, 8, 0);
  DateTime _cachedMaxEnd = DateTime(0, 1, 1, 16, 0);
  Map<String, dynamic>? _cachedDisplayCurrentClass;
  int _lastCachedIndex = -1;
  bool _lastCachedOverview = false;
  bool _cacheInitialized = false;

  // Timer references for cleanup
  Timer? _classUpdateTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
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
    _titleScaleController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _titleScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _titleScaleController, curve: Curves.easeOut),
    );
    _overviewController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _overviewScale = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _overviewController, curve: Curves.easeInOut),
    );
    _overviewFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _overviewController, curve: Curves.easeInOut),
    );
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _updateTodayIndex();
    _transitionController.value = 1.0;
    _titleScaleController.value = 1.0;
    
    // Initialize cache immediately - don't defer it
    _updateCachedDisplayData();
    _updateCurrentClass();
    
    // Update current class every 5 minutes to reduce overhead
    _classUpdateTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        _updateCurrentClass();
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
    if (!mounted || widget.schedule.isEmpty) return;

    try {
      final now = DateTime.now();
      final today = _getTodayString(now);
      final todayDay = widget.schedule.firstWhere(
        (day) => day['name'] == today,
        orElse: () => <String, dynamic>{},
      );
      final List<Map<String, dynamic>> todaySchedule = todayDay.isNotEmpty
          ? List<Map<String, dynamic>>.from(todayDay['classes'] as List<dynamic>)
          : [];

      _currentClass = _getCurrentClass(todaySchedule, now);
      _saveCurrentClass();
    } catch (e) {
      // Silently fail if update fails
    }
  }

  Future<void> _saveCurrentClass() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();

    if (_currentClass != null) {
      // In active class - save class info and end time
      await prefs.setString('class_name', _currentClass!['name'] ?? '');
      await prefs.setString('room', _currentClass!['room'] ?? '');

      final endStr = _currentClass!['end'] as String?;
      final startStr = _currentClass!['start'] as String?;
      if (endStr != null && startStr != null) {
        final end = _parseTime(endStr);
        final start = _parseTime(startStr);
        if (end != null && start != null) {
          final now = DateTime.now();
          final endDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            end.hour,
            end.minute,
          );
          final startDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            start.hour,
            start.minute,
          );
          final minutesRemaining = endDateTime.difference(now).inMinutes;
          final totalMinutes = endDateTime.difference(startDateTime).inMinutes;
          await prefs.setInt(
            'class_ends_in',
            minutesRemaining.clamp(0, 1440),
          ); // Clamp to reasonable range
          await prefs.setInt(
            'class_total_duration',
            totalMinutes.clamp(0, 1440),
          ); // Clamp to reasonable range
        }
      }
      await prefs.remove('next_class_name');
      await prefs.remove('next_class_starts_in');
    } else {
      // No active class - find next class
      await prefs.setString('class_name', '');
      await prefs.setString('room', '');
      await prefs.remove('class_ends_in');

      // Only try to find next class if we have schedule data
      if (widget.schedule.isNotEmpty) {
        final now = DateTime.now();
        final today = _getTodayString(now);
        final todayDay = widget.schedule.firstWhere(
          (day) => day['name'] == today,
          orElse: () => <String, dynamic>{},
        );
        final List<Map<String, dynamic>> todaySchedule = todayDay.isNotEmpty
            ? List<Map<String, dynamic>>.from(
                todayDay['classes'] as List<dynamic>,
              )
            : [];

        Map<String, dynamic>? nextClass;
        int? minutesToNext;

        for (final classData in todaySchedule) {
          final startStr = classData['start'] as String?;
          if (startStr != null) {
            final start = _parseTime(startStr);
            if (start != null) {
              final startDateTime = DateTime(
                now.year,
                now.month,
                now.day,
                start.hour,
                start.minute,
              );
              if (now.isBefore(startDateTime)) {
                final minutes = startDateTime.difference(now).inMinutes;
                if (nextClass == null || minutes < minutesToNext!) {
                  nextClass = classData;
                  minutesToNext = minutes;
                }
              }
            }
          }
        }

        if (nextClass != null && minutesToNext != null) {
          await prefs.setString('next_class_name', nextClass['name'] ?? '');
          await prefs.setInt(
            'next_class_starts_in',
            minutesToNext.clamp(0, 1440),
          ); // Clamp to reasonable range
        } else {
          await prefs.remove('next_class_name');
          await prefs.remove('next_class_starts_in');
        }
      } else {
        await prefs.remove('next_class_name');
        await prefs.remove('next_class_starts_in');
      }
    }
  }

  Map<String, dynamic>? _getCurrentClass(
    List<Map<String, dynamic>> todaySchedule,
    DateTime now,
  ) {
    for (final classData in todaySchedule) {
      final startStr = classData['start'] as String?;
      final endStr = classData['end'] as String?;
      if (startStr != null && endStr != null) {
        final start = _parseTime(startStr);
        final end = _parseTime(endStr);
        if (start != null && end != null) {
          final startDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            start.hour,
            start.minute,
          );
          final endDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            end.hour,
            end.minute,
          );
          if (now.isAfter(startDateTime) && now.isBefore(endDateTime)) {
            return classData;
          }
        }
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
      final adjustedHour = isPM && hour != 12
          ? hour + 12
          : (hour == 12 && !isPM ? 0 : hour);
      return DateTime(0, 1, 1, adjustedHour, minute);
    }
    return null;
  }

  int getRemainingClassesCount() {
    final now = DateTime.now();
    final today = _getTodayString(now);
    final todayDay = widget.schedule.firstWhere(
      (day) => day['name'] == today,
      orElse: () => <String, dynamic>{},
    );
    final List<Map<String, dynamic>> todaySchedule = todayDay.isNotEmpty
        ? List<Map<String, dynamic>>.from(todayDay['classes'] as List<dynamic>)
        : [];

    int count = 0;
    for (final classData in todaySchedule) {
      final endStr = classData['end'] as String?;
      if (endStr != null) {
        final end = _parseTime(endStr);
        if (end != null) {
          final endDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            end.hour,
            end.minute,
          );
          if (now.isBefore(endDateTime)) {
            count++;
          }
        }
      }
    }
    return count;
  }

  int getRemainingMinutes() {
    final now = DateTime.now();
    final today = _getTodayString(now);
    final todayDay = widget.schedule.firstWhere(
      (day) => day['name'] == today,
      orElse: () => <String, dynamic>{},
    );
    final List<Map<String, dynamic>> todaySchedule = todayDay.isNotEmpty
        ? List<Map<String, dynamic>>.from(todayDay['classes'] as List<dynamic>)
        : [];

    for (final classData in todaySchedule) {
      final endStr = classData['end'] as String?;
      if (endStr != null) {
        final end = _parseTime(endStr);
        if (end != null) {
          final endDateTime = DateTime(
            now.year,
            now.month,
            now.day,
            end.hour,
            end.minute,
          );
          if (now.isBefore(endDateTime)) {
            return endDateTime.difference(now).inMinutes;
          }
        }
      }
    }
    return 0;
  }

  void _changeDay(int newIndex) {
    if (!mounted) return;

    // Invalidate cache so it recalculates for the new day
    _lastCachedIndex = -1;

    setState(() {
      _currentIndex = newIndex;
    });
    // Use transition controller for a lightweight scale/fade effect
    _transitionController.forward(from: 0.0);
    _titleScaleController.forward(from: 0.0);
  }

  /// Interpolate between two DateTime values based on a morphAmount (0 to 1)
  DateTime _interpolateTime(DateTime start, DateTime end, double amount) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final interpolatedMinutes =
        startMinutes + (endMinutes - startMinutes) * amount;

    final hours = (interpolatedMinutes / 60).floor();
    final minutes = (interpolatedMinutes % 60).floor();

    return DateTime(0, 1, 1, hours, minutes);
  }

  String _getTodayString(DateTime now) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    return days[now.weekday % 7];
  }

  void _updateCachedDisplayData() {
    try {
      // Only update if index or overview state changed
      if (_cacheInitialized &&
          _lastCachedIndex == _currentIndex &&
          _lastCachedOverview == _isOverview) {
        // Already cached, no need to recalculate
        return;
      }

      _lastCachedIndex = _currentIndex;
      _lastCachedOverview = _isOverview;

      // Handle empty schedule
      if (widget.schedule.isEmpty) {
        _cachedDisplayClasses = [];
        _cachedMinStart = DateTime(0, 1, 1, 8, 0);
        _cachedMaxEnd = DateTime(0, 1, 1, 16, 0);
        _cachedDisplayCurrentClass = null;
        _cacheInitialized = true;
        return;
      }

    _cachedDisplayClasses = _isOverview
        ? (_currentIndex >= 0 &&
                  _currentIndex < widget.schedule.length &&
                  widget.schedule[_currentIndex]['classes'] != null
              ? (widget.schedule[_currentIndex]['classes'] as List<dynamic>)
                    .cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[])
        : (_currentIndex >= 0 &&
                  _currentIndex < widget.schedule.length &&
                  widget.schedule[_currentIndex]['classes'] != null
              ? (widget.schedule[_currentIndex]['classes'] as List<dynamic>)
                    .cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[]);

    DateTime? minStart;
    DateTime? maxEnd;
    for (final classData in _cachedDisplayClasses) {
      final startStr = classData['start'] as String?;
      final endStr = classData['end'] as String?;
      if (startStr != null && endStr != null) {
        final start = _parseTime(startStr);
        final end = _parseTime(endStr);
        if (start != null && end != null) {
          if (minStart == null || start.isBefore(minStart)) minStart = start;
          if (maxEnd == null || end.isAfter(maxEnd)) maxEnd = end;
        }
      }
    }

    // Round school hours for proper display BEFORE morphing
    if (minStart != null && maxEnd != null) {
      _cachedMinStart = DateTime(0, 1, 1, minStart.hour, 0);
      _cachedMaxEnd = maxEnd.minute > 0
          ? DateTime(0, 1, 1, maxEnd.hour + 1, 0)
          : DateTime(0, 1, 1, maxEnd.hour, 0);
    } else {
      _cachedMinStart = DateTime(0, 1, 1, 8, 0);
      _cachedMaxEnd = DateTime(0, 1, 1, 16, 0);
    }

    final isToday = _currentIndex == _todayIndex;
    _cachedDisplayCurrentClass = _isOverview
        ? (isToday ? _getCurrentClass(_cachedDisplayClasses, DateTime.now()) : null)
        : (isToday ? _currentClass : null);
    
    _cacheInitialized = true;
    } catch (e) {
      // If cache update fails, use safe defaults
      _cachedDisplayClasses = [];
      _cachedMinStart = DateTime(0, 1, 1, 8, 0);
      _cachedMaxEnd = DateTime(0, 1, 1, 16, 0);
      _cachedDisplayCurrentClass = null;
      _cacheInitialized = true;
    }
  }

  @override
  void dispose() {
    _classUpdateTimer?.cancel();
    _animationController.dispose();
    _transitionController.dispose();
    _titleScaleController.dispose();
    _overviewController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Update cache data if state changed
    _updateCachedDisplayData();

    return WearScaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: () {
                if (!mounted) return;
                setState(() {
                  _isOverview = !_isOverview;
                  if (_isOverview) {
                    _overviewController.forward();
                    _rotationController.forward();
                    // Animate morph to 24-hour view
                    _animationController.forward();
                  } else {
                    _overviewController.reverse();
                    _rotationController.reverse();
                    // Animate morph back to school-hours view
                    _animationController.reverse();
                  }
                });
              },
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    widget.schedule.isNotEmpty) {
                  if (details.primaryVelocity! < -200) {
                    // Swipe up
                    final newIndex =
                        (_currentIndex + 1) % widget.schedule.length;
                    _changeDay(newIndex);
                  } else if (details.primaryVelocity! > 200) {
                    // Swipe down
                    final newIndex =
                        (_currentIndex - 1 + widget.schedule.length) %
                        widget.schedule.length;
                    _changeDay(newIndex);
                  }
                }
              },
              onLongPress: () {
                if (!mounted) return;
                final grades = context.read<ScheduleProvider>().classGrades;
                if (grades == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => GradeBookScreen(
                      schedule: _cachedDisplayClasses,
                      attendanceData: widget.attendanceData,
                      classGrades: grades,
                    ),
                  ),
                );
              },
              child: Stack(
                children: [
                  ScaleTransition(
                    scale: _overviewScale,
                    child: Stack(
                      children: [
                        // Circular schedule display with morphing transition
                        AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            final t = _animationController.value;

                            // Interpolate between school hours and 24-hour view for smooth morphing
                            final morphedMinStart = _interpolateTime(
                              _cachedMinStart,
                              DateTime(0, 1, 1, 0, 0),
                              t,
                            );
                            final morphedMaxEnd = _interpolateTime(
                              _cachedMaxEnd,
                              DateTime(0, 1, 1, 23, 59),
                              t,
                            );

                            final scheduleWidget = ScaleTransition(
                              scale: _scaleAnimation,
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: DaySchedulePainter(
                                  classes: _cachedDisplayClasses,
                                  currentClass: _cachedDisplayCurrentClass,
                                  minStart: morphedMinStart,
                                  maxEnd: morphedMaxEnd,
                                  schoolMinStart: _cachedMinStart,
                                  schoolMaxEnd: _cachedMaxEnd,
                                  is24Hour: t > 0.5,
                                  morphAmount: t,
                                ),
                                foregroundPainter:
                                    ((_currentIndex == _todayIndex) ||
                                        _isOverview)
                                    ? TimeIndicatorPainter(
                                        minStart: morphedMinStart,
                                        maxEnd: morphedMaxEnd,
                                        is24Hour: t > 0.5,
                                        morphAmount: t,
                                        showAnalogHands: _isOverview,
                                      )
                                    : null,
                              ),
                            );

                            return scheduleWidget;
                          },
                        ),

                        // Center display with smooth fade and scale
                        Center(
                          child: FadeTransition(
                            opacity: _titleFadeAnimation,
                            child: ScaleTransition(
                              scale: _titleScaleAnimation,
                              child: FadeTransition(
                                opacity: _overviewFade,
                                child: _currentIndex == _todayIndex
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_currentClass != null) ...[
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withOpacity(
                                                  0.5,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                  color: Colors.blue
                                                      .withOpacity(0.5),
                                                ),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(
                                                    _currentClass!['name'] ??
                                                        'Unknown',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  Text(
                                                    _currentClass!['room'] ??
                                                        'N/A',
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
                                                  _getScheduleName(
                                                    _currentIndex,
                                                  ),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Text(
                                                  "Today",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w300,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      )
                                    : Text(
                                        _getScheduleName(_currentIndex),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                  // Arc texts for overview
                  if (_isOverview && getRemainingClassesCount() > 0) ...[
                    Positioned(
                      top: 15,
                      left: 0,
                      right: 0,
                      height: 80,
                      child: Text(
                        'Classes: ${getRemainingClassesCount()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'RobotoMono',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (getRemainingMinutes() > 0)
                    Positioned(
                      bottom: -42,
                      left: 0,
                      right: 0,
                      height: 80,
                      child: Text(
                        '${getRemainingMinutes()}m',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'RobotoFlex',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!_isOverview)
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

  String _getScheduleName(int index) {
    if (index >= 0 && index < widget.schedule.length) {
      final day = widget.schedule[index];
      if (day.containsKey('name')) {
        return day['name'] as String? ?? 'Unknown';
      }
    }
    return 'Unknown';
  }
}

class DaySchedulePainter extends CustomPainter {
  final List<Map<String, dynamic>> classes;
  final Map<String, dynamic>? currentClass;
  final DateTime? minStart; // Morphed time for hour markers
  final DateTime? maxEnd; // Morphed time for hour markers
  final DateTime? schoolMinStart; // Original school time for class positioning
  final DateTime? schoolMaxEnd; // Original school time for class positioning
  final bool is24Hour;
  final double morphAmount;

  DaySchedulePainter({
    required this.classes,
    this.currentClass,
    this.minStart,
    this.maxEnd,
    this.schoolMinStart,
    this.schoolMaxEnd,
    this.is24Hour = false,
    this.morphAmount = 0.0,
  });

  DateTime? _parseTime(String timeStr) {
    return parseTimeSync(timeStr);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;
    if (radius <= 0) return;

    // Draw background circle
    final bgPaint = Paint()
      ..color = Colors.grey.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, bgPaint);

    // Use morphed times for hour marker display
    final displayMinStart = minStart ?? DateTime(0, 1, 1, 8, 0);
    final displayMaxEnd = maxEnd ?? DateTime(0, 1, 1, 16, 0);

    // Use original school times for class positioning
    final classMinStart = schoolMinStart ?? DateTime(0, 1, 1, 8, 0);
    final classMaxEnd = schoolMaxEnd ?? DateTime(0, 1, 1, 16, 0);

    // Draw clock markers based on morphed times for smooth transition
    final totalMinutes = displayMaxEnd
        .difference(displayMinStart)
        .inMinutes
        .toDouble();
    if (totalMinutes > 0) {
      final opacity = (1.0 - (morphAmount * 0.3)).clamp(0.0, 1.0);

      // Reuse TextPainter for hour labels
      final hourTextPainter = TextPainter(textDirection: TextDirection.ltr);

      // Draw hour markers from morphed start to morphed end
      // Use integer-based loop to prevent DateTime day-wrapping infinite loop
      final int startHour = displayMinStart.hour;
      final int endHour = displayMaxEnd.hour;
      final int numHours = (endHour >= startHour) ? (endHour - startHour + 1) : 0;
      for (int i = 0; i < numHours; i++) {
        final double tickMinutes = i * 60.0;
        final ratio = (tickMinutes / totalMinutes).clamp(0.0, 1.0);
        final angle = ratio * 2 * pi - pi / 2;

        final innerRadius = radius - 20;
        final markerStart = Offset(
          center.dx + innerRadius * cos(angle),
          center.dy + innerRadius * sin(angle),
        );
        final markerEnd = Offset(
          center.dx + radius * cos(angle),
          center.dy + radius * sin(angle),
        );

        final markerPaint = Paint()
          ..color = Colors.white.withOpacity(0.8 * opacity)
          ..strokeWidth = 2;
        canvas.drawLine(markerStart, markerEnd, markerPaint);

        final textRadius = innerRadius - 15;
        final textX = center.dx + textRadius * cos(angle);
        final textY = center.dy + textRadius * sin(angle);

        var displayHour = (startHour + i) % 12;
        displayHour = displayHour == 0 ? 12 : displayHour;

        hourTextPainter.text = TextSpan(
          text: displayHour.toString(),
          style: TextStyle(
            color: Colors.white.withOpacity(opacity),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        hourTextPainter.layout();
        hourTextPainter.paint(
          canvas,
          Offset(textX - hourTextPainter.width / 2, textY - hourTextPainter.height / 2),
        );
      }
    }

    if (classes.isEmpty) return;

    // Classes are assumed to be sorted by start time

    // Draw class sectors - use original school times for positioning
    _drawClassesOn12Hour(
      canvas,
      center,
      radius,
      classes,
      classMinStart,
      classMaxEnd,
    );

    // Draw center circle
    final centerCircleRadius = 40.0;
    final centerPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, centerCircleRadius, centerPaint);
  }

  void _drawClassesOn12Hour(
    Canvas canvas,
    Offset center,
    double radius,
    List<Map<String, dynamic>> sortedClasses,
    DateTime schoolMinStart,
    DateTime schoolMaxEnd,
  ) {
    const fullCircle = 2 * pi;

    // Use morphed times for smooth positioning during transition
    final referenceStart = minStart ?? schoolMinStart;
    final referenceEnd = maxEnd ?? schoolMaxEnd;
    final totalMinutes = referenceEnd
        .difference(referenceStart)
        .inMinutes
        .toDouble();
    if (totalMinutes <= 0) return; // No valid time range

    // Reuse TextPainter for class labels
    final classTextPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final classData in sortedClasses) {
      final startStr = classData['start'] as String?;
      final endStr = classData['end'] as String?;
      if (startStr == null || endStr == null) continue;

      final startTime = _parseTime(startStr);
      final endTime = _parseTime(endStr);
      if (startTime == null || endTime == null) continue;

      final startMinutes = startTime
          .difference(referenceStart)
          .inMinutes
          .toDouble();
      final endMinutes = endTime
          .difference(referenceStart)
          .inMinutes
          .toDouble();

      // Map to clock - spread hours across full circle
      final startRatio = (startMinutes / totalMinutes).clamp(0.0, 1.0);
      final endRatio = (endMinutes / totalMinutes).clamp(0.0, 1.0);

      final startAngle = startRatio * fullCircle - pi / 2;
      final endAngle = endRatio * fullCircle - pi / 2;
      final sweepAngle = endAngle - startAngle;

      if (sweepAngle <= 0) continue;

      final className = classData['name'] as String? ?? 'Unknown';
      final isCurrent =
          currentClass != null &&
          classData['name'] == currentClass!['name'] &&
          classData['start'] == currentClass!['start'];

      // Generate rainbow color based on start angle
      final normalizedAngle = (startAngle + pi / 2) % (2 * pi);
      final hue = (normalizedAngle / (2 * pi)) * 360;
      final baseColor = HSVColor.fromAHSV(
        1.0,
        hue,
        isCurrent ? 1.0 : 0.8,
        isCurrent ? 1.0 : 0.9,
      ).toColor();

      final classPaint = Paint()
        ..color = baseColor
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        classPaint,
      );

      // Draw label
      final labelAngle = startAngle + sweepAngle / 2;
      final labelRadius = radius - 25;
      final labelX = center.dx + labelRadius * cos(labelAngle);
      final labelY = center.dy + labelRadius * sin(labelAngle);

      final room = classData['room'] as String? ?? 'N/A';
      final displayName = _abbreviateClassName(className);
      final displayRoom = _abbreviateRoom(room);

      final textColor = baseColor.computeLuminance() > 0.5
          ? Colors.black
          : Colors.white;
      final roomTextColor = textColor.withOpacity(0.7);

      // Smooth opacity transition for text
      final textOpacity = 1.0 - (morphAmount * 0.2);

      classTextPainter.text = TextSpan(
        children: [
          TextSpan(
            text: displayName,
            style: TextStyle(
              color: textColor.withOpacity(textOpacity),
              fontSize: 8,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          TextSpan(text: '\n'),
          TextSpan(
            text: displayRoom,
            style: TextStyle(
              color: roomTextColor.withOpacity(textOpacity),
              fontSize: 7,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w400,
            ),
          ),
        ],
      );
      classTextPainter.layout();
      classTextPainter.paint(
        canvas,
        Offset(labelX - classTextPainter.width / 2, labelY - classTextPainter.height / 2),
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
  bool shouldRepaint(covariant DaySchedulePainter oldDelegate) {
    return !identical(classes, oldDelegate.classes) ||
        !identical(currentClass, oldDelegate.currentClass) ||
        morphAmount != oldDelegate.morphAmount ||
        minStart != oldDelegate.minStart ||
        maxEnd != oldDelegate.maxEnd;
  }
}

class TimeIndicatorPainter extends CustomPainter {
  final DateTime? minStart;
  final DateTime? maxEnd;
  final bool is24Hour;
  final double morphAmount;
  final bool showAnalogHands;

  TimeIndicatorPainter({
    this.minStart,
    this.maxEnd,
    this.is24Hour = false,
    this.morphAmount = 0.0,
    this.showAnalogHands = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    if (showAnalogHands) {
      // Draw analog clock hands
      final now = DateTime.now();

      // Draw hour hand
      final hourAngle = (now.hour % 12 + now.minute / 60.0) * 30 * pi / 180 - pi / 2;
      final hourHandLength = radius * 0.5;
      final hourHandEnd = Offset(
        center.dx + hourHandLength * cos(hourAngle),
        center.dy + hourHandLength * sin(hourAngle),
      );
      final hourPaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, hourHandEnd, hourPaint);

      // Draw minute hand
      final minuteAngle = now.minute * 6 * pi / 180 - pi / 2;
      final minuteHandLength = radius * 0.7;
      final minuteHandEnd = Offset(
        center.dx + minuteHandLength * cos(minuteAngle),
        center.dy + minuteHandLength * sin(minuteAngle),
      );
      final minutePaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, minuteHandEnd, minutePaint);

      // Draw second hand
      final secondAngle = now.second * 6 * pi / 180 - pi / 2;
      final secondHandLength = radius * 0.8;
      final secondHandEnd = Offset(
        center.dx + secondHandLength * cos(secondAngle),
        center.dy + secondHandLength * sin(secondAngle),
      );
      final secondPaint = Paint()
        ..color = Colors.red.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center, secondHandEnd, secondPaint);

      // Draw center hub
      final hubPaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 6, hubPaint);

      final hubOutlinePaint = Paint()
        ..color = Colors.grey.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, 8, hubOutlinePaint);
    } else {
      // Draw progress marker throughout the day
      if (minStart == null || maxEnd == null) return;

      final now = DateTime.now();
      final currentTime = DateTime(0, 1, 1, now.hour, now.minute, now.second);

      // Use the morphed reference times for smooth positioning
      final referenceStart = minStart!;
      final referenceEnd = maxEnd!;

      final totalMinutes = referenceEnd
          .difference(referenceStart)
          .inMinutes
          .toDouble();
      final currentMinutes = currentTime
          .difference(referenceStart)
          .inMinutes
          .toDouble();

      if (currentMinutes < 0 || currentMinutes > totalMinutes) return;

      // Map current time to 12-hour clock position
      final progress = (currentMinutes / totalMinutes).clamp(0.0, 1.0);
      const fullCircle = 2 * pi;
      final angle = progress * fullCircle - pi / 2;

      // Draw progress hand (longer, more visible)
      final handRadius = radius * 0.75;
      final handEndPoint = Offset(
        center.dx + handRadius * cos(angle),
        center.dy + handRadius * sin(angle),
      );

      final handPaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(center, handEndPoint, handPaint);

      // Draw glow effect
      final glowPaint = Paint()
        ..color = Colors.blue.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;
      canvas.drawLine(center, handEndPoint, glowPaint);

      // Draw center hub
      final hubPaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.fill;

      final hubOutlinePaint = Paint()
        ..color = Colors.blue.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, 6, hubPaint);
      canvas.drawCircle(center, 8, hubOutlinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant TimeIndicatorPainter oldDelegate) {
    return morphAmount != oldDelegate.morphAmount ||
        showAnalogHands != oldDelegate.showAnalogHands ||
        true; // Always repaint for smooth animations
  }
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
      final adjustedHour = isPM && hour != 12
          ? hour + 12
          : (hour == 12 && !isPM ? 0 : hour);
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
    final endDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      endTime.hour,
      endTime.minute,
    );
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false; // Only repaint when explicitly requested
}

class TodayScheduleScreen extends StatelessWidget {
  final List<Map<String, dynamic>> schedule;
  final String title;
  final Map<String, dynamic>? attendanceData;

  const TodayScheduleScreen({
    super.key,
    required this.schedule,
    this.title = 'Today\'s Schedule',
    this.attendanceData,
  });

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
                        ? BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          )
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
                                  color: isCurrent
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                ),
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
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
                        _buildInfoRow(
                          'Time',
                          '${classData['start'] ?? 'N/A'} - ${classData['end'] ?? 'N/A'}',
                        ),
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
            style: const TextStyle(color: Colors.white, fontSize: 12),
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
        final startDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          start.hour,
          start.minute,
        );
        final endDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          end.hour,
          end.minute,
        );
        return now.isAfter(startDateTime) && now.isBefore(endDateTime);
      }
    }
    return false;
  }

  DateTime? _parseTime(String timeStr) {
    final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)');
    final match = regex.firstMatch(timeStr.trim());
    if (match != null) {
      final hour = int.parse(match.group(1)!);
      final minute = int.parse(match.group(2)!);
      final isPM = match.group(3) == 'PM';
      final adjustedHour = isPM && hour != 12
          ? hour + 12
          : (hour == 12 && !isPM ? 0 : hour);
      return DateTime(0, 1, 1, adjustedHour, minute);
    }
    return null;
  }
}

class GradeBookScreen extends StatelessWidget {
  final List<Map<String, dynamic>> schedule;
  final Map<String, dynamic>? attendanceData;
  final Map<String, dynamic> classGrades;

  const GradeBookScreen({
    super.key,
    required this.schedule,
    this.attendanceData,
    required this.classGrades,
  });

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
              itemCount: schedule.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final gpa = context.read<ScheduleProvider>().gpa;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: Theme.of(context).cardTheme.color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Center(
                        child: Text(
                          'GPA: ${gpa.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final classIndex = index - 1;
                final classData = schedule[classIndex];
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
              style: const TextStyle(color: Colors.white, fontSize: 12),
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
          style: const TextStyle(fontSize: 10, color: Colors.white70),
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
          style: const TextStyle(fontSize: 10, color: Colors.white70),
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
