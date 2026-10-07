import 'package:go_router/go_router.dart';

import '../../features/classes/classes_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/payments/encaissement_screen.dart';
import '../../features/payments/history_screen.dart';
import '../../features/payments/receipt_screen.dart';
import '../../features/reports/unpaid_report_screen.dart';
import '../../features/settings/school_year_settings_screen.dart';
import '../../features/students/promotion_screen.dart';
import '../../features/students/student_detail_screen.dart';
import '../../features/students/student_form_screen.dart';
import '../../features/students/students_list_screen.dart';
import '../../features/tariffs/tariffs_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/auth_gate.dart';

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AuthGate(
        child: AppShell(location: state.uri.path, child: child),
      ),
      routes: [
        GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
        GoRoute(
          path: '/students',
          builder: (_, _) => const StudentsListScreen(),
        ),
        GoRoute(
          path: '/students/new',
          builder: (_, _) => const StudentFormScreen(),
        ),
        GoRoute(
          path: '/students/promotion',
          builder: (_, _) => const PromotionScreen(),
        ),
        GoRoute(
          path: '/students/:id/edit',
          builder: (_, state) => StudentFormScreen(
            studentId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/students/:id',
          builder: (_, state) => StudentDetailScreen(
            studentId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(path: '/classes', builder: (_, _) => const ClassesScreen()),
        GoRoute(
          path: '/payments',
          builder: (_, state) => EncaissementScreen(
            initialStudentId: int.tryParse(
              state.uri.queryParameters['student'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/payments/:paymentId/receipt',
          builder: (_, state) => ReceiptScreen(
            paymentId: int.parse(state.pathParameters['paymentId']!),
            backToHistory: state.uri.queryParameters['back'] == 'history',
          ),
        ),
        GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
        GoRoute(path: '/tariffs', builder: (_, _) => const TariffsScreen()),
        GoRoute(
          path: '/reports/unpaid',
          builder: (_, _) => const UnpaidReportScreen(),
        ),
        GoRoute(
          path: '/settings/school-years',
          builder: (_, _) => const SchoolYearSettingsScreen(),
        ),
      ],
    ),
  ],
);
