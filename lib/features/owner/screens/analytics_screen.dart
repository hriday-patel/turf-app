import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../data/models/booking_model.dart';
import '../../../core/constants/enums.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/turf_provider.dart';
import '../providers/booking_provider.dart';

/// Analytics Screen
/// Pro feature (₹100 unlock) with revenue charts, peak hours, utilization
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isProUnlocked = false;
  bool _isLoading = true;
  String _selectedPeriod = '7days';

  // Analytics data
  double _totalRevenue = 0;
  int _totalBookings = 0;
  int _cancelledBookings = 0;
  Map<int, double> _hourlyBookings = {};
  Map<int, double> _dailyRevenue = {};
  Map<String, int> _netUtilization = {};

  @override
  void initState() {
    super.initState();
    _checkProStatus();
    _loadAnalytics();
  }

  void _checkProStatus() {
    // Check shared_preferences for pro unlock status
    // For now, allow direct unlock via UI
    setState(() => _isProUnlocked = true); // Default unlocked for owners
  }

  void _loadAnalytics() {
    final bookingProvider = Provider.of<BookingProvider>(context, listen: false);
    final bookings = bookingProvider.bookings;

    final now = DateTime.now();
    final daysBack = _selectedPeriod == '7days' ? 7 : _selectedPeriod == '30days' ? 30 : 90;
    final cutoff = now.subtract(Duration(days: daysBack));

    final filtered = bookings.where((b) {
      final bDate = DateTime.tryParse(b.bookingDate);
      return bDate != null && bDate.isAfter(cutoff);
    }).toList();

    double totalRev = 0;
    int totalBook = 0;
    int cancelled = 0;
    final Map<int, double> hourly = {};
    final Map<int, double> daily = {};
    final Map<String, int> netUtil = {};

    for (final b in filtered) {
      if (b.bookingStatus == BookingStatus.cancelled) {
        cancelled++;
        continue;
      }
      totalBook++;
      totalRev += b.amount;

      // Peak hours
      final hour = int.tryParse(b.startTime.split(':')[0]) ?? 0;
      hourly[hour] = (hourly[hour] ?? 0) + 1;

      // Daily revenue
      final bDate = DateTime.tryParse(b.bookingDate);
      if (bDate != null) {
        final dayIndex = now.difference(bDate).inDays;
        if (dayIndex >= 0 && dayIndex < daysBack) {
          daily[dayIndex] = (daily[dayIndex] ?? 0) + b.amount;
        }
      }

      // Net utilization
      final netKey = 'Net ${b.netNumber}';
      netUtil[netKey] = (netUtil[netKey] ?? 0) + 1;
    }

    setState(() {
      _totalRevenue = totalRev;
      _totalBookings = totalBook;
      _cancelledBookings = cancelled;
      _hourlyBookings = hourly;
      _dailyRevenue = daily;
      _netUtilization = netUtil;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GlassScaffoldBackground(
        child: SafeArea(
          child: Column(
            children: [
              GlassAppBar(
                title: 'Analytics Dashboard',
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildPeriodSelector(),
                  ),
                ],
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : !_isProUnlocked
                        ? _buildProGate()
                        : _buildAnalyticsContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return DropdownButton<String>(
      value: _selectedPeriod,
      dropdownColor: AppColors.surface,
      underline: const SizedBox(),
      icon: const Icon(Icons.arrow_drop_down, color: AppColors.textPrimary),
      items: const [
        DropdownMenuItem(value: '7days', child: Text('7 Days', style: TextStyle(color: AppColors.textPrimary))),
        DropdownMenuItem(value: '30days', child: Text('30 Days', style: TextStyle(color: AppColors.textPrimary))),
        DropdownMenuItem(value: '90days', child: Text('90 Days', style: TextStyle(color: AppColors.textPrimary))),
      ],
      onChanged: (val) {
        if (val != null) {
          setState(() => _selectedPeriod = val);
          _loadAnalytics();
        }
      },
    );
  }

  Widget _buildProGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 80, color: AppColors.primary.withOpacity(0.5)),
            const SizedBox(height: 24),
            const Text(
              'Unlock Analytics Pro',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Get access to revenue charts, peak hours analysis, net utilization metrics, and more.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _isProUnlocked = true);
                  _loadAnalytics();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Unlock for ₹100',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards
          _buildSummaryCards(),
          const SizedBox(height: 24),

          // Revenue Chart
          _buildSectionTitle('Revenue Trend'),
          _buildRevenueChart(),
          const SizedBox(height: 24),

          // Peak Hours
          _buildSectionTitle('Peak Hours'),
          _buildPeakHoursChart(),
          const SizedBox(height: 24),

          // Net Utilization
          _buildSectionTitle('Net Utilization'),
          _buildNetUtilization(),
          const SizedBox(height: 24),

          // Cancellation Ratio
          _buildSectionTitle('Booking Stats'),
          _buildBookingStats(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final cancellationRate = (_totalBookings + _cancelledBookings) > 0
        ? (_cancelledBookings / (_totalBookings + _cancelledBookings) * 100)
        : 0.0;

    return Row(
      children: [
        Expanded(child: _buildSummaryCard('Revenue', '₹${_totalRevenue.toInt()}', AppColors.success, Icons.currency_rupee)),
        const SizedBox(width: 12),
        Expanded(child: _buildSummaryCard('Bookings', '$_totalBookings', AppColors.primary, Icons.event_available)),
        const SizedBox(width: 12),
        Expanded(child: _buildSummaryCard('Cancelled', '${cancellationRate.toStringAsFixed(1)}%', AppColors.error, Icons.cancel_outlined)),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    final daysBack = _selectedPeriod == '7days' ? 7 : _selectedPeriod == '30days' ? 30 : 90;
    final spots = <FlSpot>[];
    for (int i = daysBack - 1; i >= 0; i--) {
      spots.add(FlSpot((daysBack - 1 - i).toDouble(), _dailyRevenue[i] ?? 0));
    }

    if (spots.every((s) => s.y == 0)) {
      return _buildEmptyChart('No revenue data for this period');
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.glassFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget: Text('Days', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              axisNameSize: 18,
              sideTitles: const SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Text('Revenue (₹)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              axisNameSize: 18,
              sideTitles: const SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              isStrokeCapRound: true,
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withOpacity(0.1),
              ),
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeakHoursChart() {
    if (_hourlyBookings.isEmpty) {
      return _buildEmptyChart('No booking data for peak hours');
    }

    final bars = <BarChartGroupData>[];
    for (int h = 0; h < 24; h++) {
      bars.add(BarChartGroupData(
        x: h,
        barRods: [
          BarChartRodData(
            toY: _hourlyBookings[h] ?? 0,
            color: _getHourColor(h),
            width: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ));
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.glassFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              axisNameWidget: Text('Bookings', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              axisNameSize: 18,
              sideTitles: const SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget: Text('Hour of Day', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              axisNameSize: 18,
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() % 4 == 0) {
                    return Text('${value.toInt()}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary));
                  }
                  return const SizedBox();
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: bars,
        ),
      ),
    );
  }

  Color _getHourColor(int hour) {
    if (hour >= 6 && hour < 12) return AppColors.warning; // Morning
    if (hour >= 12 && hour < 18) return AppColors.secondary; // Afternoon
    if (hour >= 18 && hour < 24) return AppColors.primary; // Evening
    return Colors.blueGrey; // Night
  }

  Widget _buildNetUtilization() {
    if (_netUtilization.isEmpty) {
      return _buildEmptyChart('No net utilization data');
    }

    final total = _netUtilization.values.fold<int>(0, (a, b) => a + b);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.glassFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
      child: Column(
        children: _netUtilization.entries.map((entry) {
          final pct = total > 0 ? (entry.value / total * 100) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${entry.value} bookings (${pct.toStringAsFixed(1)}%)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBookingStats() {
    final total = _totalBookings + _cancelledBookings;
    final confirmedPct = total > 0 ? (_totalBookings / total * 100) : 0.0;
    final cancelledPct = total > 0 ? (_cancelledBookings / total * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.glassFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 150,
              child: total > 0
                  ? PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(
                            value: _totalBookings.toDouble(),
                            color: AppColors.success,
                            title: '${confirmedPct.toStringAsFixed(0)}%',
                            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            radius: 50,
                          ),
                          PieChartSectionData(
                            value: _cancelledBookings.toDouble(),
                            color: AppColors.error,
                            title: '${cancelledPct.toStringAsFixed(0)}%',
                            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            radius: 50,
                          ),
                        ],
                        sectionsSpace: 2,
                      ),
                    )
                  : Center(child: Text('No data', style: TextStyle(color: AppColors.textSecondary))),
            ),
          ),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLegendItem(AppColors.success, 'Confirmed', '$_totalBookings'),
              const SizedBox(height: 8),
              _buildLegendItem(AppColors.error, 'Cancelled', '$_cancelledBookings'),
              const SizedBox(height: 8),
              _buildLegendItem(Colors.blueGrey, 'Total', '$total'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, String value) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildEmptyChart(String message) {
    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.glassFill, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.glassBorder)),
      child: Center(
        child: Text(message, style: TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }
}
