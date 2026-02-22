// test/helpers/mock_factories.dart
//
// Mocktail Mock classes for services and repositories used in widget tests.

import 'package:mocktail/mocktail.dart';
import 'package:weldqai_app/core/services/subscription_service.dart';
import 'package:weldqai_app/core/repositories/report_repository.dart';

class MockSubscriptionService extends Mock implements SubscriptionService {}

class MockReportRepository extends Mock implements ReportRepository {}
