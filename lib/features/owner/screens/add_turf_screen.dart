import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../config/colors.dart';
import '../../../core/constants/strings.dart';
import '../../../core/constants/enums.dart';
import '../../../app/routes.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/turf_provider.dart';

/// Add Turf Screen
/// Multi-step form to add a new turf with pricing rules
class AddTurfScreen extends StatefulWidget {
  const AddTurfScreen({super.key});

  @override
  State<AddTurfScreen> createState() => _AddTurfScreenState();
}

class _AddTurfScreenState extends State<AddTurfScreen> {
  final Uuid _uuid = const Uuid();
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Form Keys
  final _basicFormKey = GlobalKey<FormState>();
  final _scheduleFormKey = GlobalKey<FormState>();
  final _pricingFormKey = GlobalKey<FormState>();

  // Basic Info Controllers
  final _turfNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  TurfType _selectedTurfType = TurfType.boxCricket;

  // Schedule Controllers
  TimeOfDay _openTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 23, minute: 0);
  int _slotDuration = 60;
  List<String> _selectedDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  // Pricing Controllers
  final _weekdayDayPriceController = TextEditingController(text: '1000');
  final _weekdayNightPriceController = TextEditingController(text: '1200');
  final _saturdayDayPriceController = TextEditingController(text: '1400');
  final _saturdayNightPriceController = TextEditingController(text: '1600');
  final _sundayDayPriceController = TextEditingController(text: '1500');
  final _sundayNightPriceController = TextEditingController(text: '1700');
  final _holidayDayPriceController = TextEditingController(text: '1800');
  final _holidayNightPriceController = TextEditingController(text: '2000');
  TimeOfDay _nightStartTime = const TimeOfDay(hour: 18, minute: 0);

  // Images
  final List<File> _selectedImages = [];
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _pageController.dispose();
    _turfNameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    _weekdayDayPriceController.dispose();
    _weekdayNightPriceController.dispose();
    _saturdayDayPriceController.dispose();
    _saturdayNightPriceController.dispose();
    _sundayDayPriceController.dispose();
    _sundayNightPriceController.dispose();
    _holidayDayPriceController.dispose();
    _holidayNightPriceController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0 && !_basicFormKey.currentState!.validate()) return;
    if (_currentStep == 1 && !_scheduleFormKey.currentState!.validate()) return;
    if (_currentStep == 2 && !_pricingFormKey.currentState!.validate()) return;

    if (_currentStep < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images.map((x) => File(x.path)));
        });
      }
    } catch (e) {
      _showError('Failed to pick images: $e');
    }
  }

  Future<void> _submitTurf() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);
      final storageService = StorageService();

      // Create pricing rules
      final openTimeStr = '${_openTime.hour.toString().padLeft(2, '0')}:${_openTime.minute.toString().padLeft(2, '0')}';
      final closeTimeStr = '${_closeTime.hour.toString().padLeft(2, '0')}:${_closeTime.minute.toString().padLeft(2, '0')}';
      final nightStartStr = '${_nightStartTime.hour.toString().padLeft(2, '0')}:${_nightStartTime.minute.toString().padLeft(2, '0')}';

      final pricingRules = PricingRules(
        weekday: DayPricing(
          day: PricingRule(
            start: openTimeStr,
            end: nightStartStr,
            price: double.parse(_weekdayDayPriceController.text),
          ),
          night: PricingRule(
            start: nightStartStr,
            end: closeTimeStr,
            price: double.parse(_weekdayNightPriceController.text),
          ),
        ),
        saturday: DayPricing(
          day: PricingRule(
            start: openTimeStr,
            end: nightStartStr,
            price: double.parse(_saturdayDayPriceController.text),
          ),
          night: PricingRule(
            start: nightStartStr,
            end: closeTimeStr,
            price: double.parse(_saturdayNightPriceController.text),
          ),
        ),
        sunday: DayPricing(
          day: PricingRule(
            start: openTimeStr,
            end: nightStartStr,
            price: double.parse(_sundayDayPriceController.text),
          ),
          night: PricingRule(
            start: nightStartStr,
            end: closeTimeStr,
            price: double.parse(_sundayNightPriceController.text),
          ),
        ),
        holiday: DayPricing(
          day: PricingRule(
            start: openTimeStr,
            end: nightStartStr,
            price: double.parse(_holidayDayPriceController.text),
          ),
          night: PricingRule(
            start: nightStartStr,
            end: closeTimeStr,
            price: double.parse(_holidayNightPriceController.text),
          ),
        ),
      );

      // Pre-generate turf ID to associate images
      final turfId = _uuid.v4();

      // Upload images first (if any)
      List<TurfImage> turfImages = [];
      if (_selectedImages.isNotEmpty) {
        try {
          final imageUrls = await storageService.uploadMultipleTurfImages(
            imageFiles: _selectedImages,
            turfId: turfId,
          );
          
          turfImages = imageUrls.map((url) => TurfImage(
            url: url,
            type: TurfImageType.ground,
          )).toList();
        } catch (e) {
          // If image upload fails, we show error and stop
          setState(() => _isLoading = false);
          _showError('Failed to upload images: $e');
          return;
        }
      }

      // Create turf
      final resultId = await turfProvider.addTurf(
        turfId: turfId,
        ownerId: authProvider.currentUserId!,
        turfName: _turfNameController.text.trim(),
        city: _cityController.text.trim(),
        address: _addressController.text.trim(),
        turfType: _selectedTurfType,
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        openTime: openTimeStr,
        closeTime: closeTimeStr,
        slotDurationMinutes: _slotDuration,
        daysOpen: _selectedDays,
        pricingRules: pricingRules,
        images: turfImages,
      );

      setState(() => _isLoading = false);

      if (resultId != null && mounted) {
        // Success!
        _showSuccess(AppStrings.turfAddedSuccess);
        Navigator.pushReplacementNamed(context, AppRoutes.verificationPending);
      } else if (mounted) {
        _showError(turfProvider.errorMessage ?? 'Failed to add turf');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to add turf: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add New Turf'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: [
          // Step Indicator
          _buildStepIndicator(),
          
          // Form Pages
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBasicInfoStep(),
                _buildScheduleStep(),
                _buildPricingStep(),
                _buildImagesStep(),
              ],
            ),
          ),
          
          // Navigation Buttons
          _buildNavigationButtons(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Basic Info', 'Schedule', 'Pricing', 'Images'];
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      color: Colors.white,
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index <= _currentStep;
          final isCompleted = index < _currentStep;
          
          return Expanded(
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : AppColors.disabled,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, color: Colors.white, size: 18)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isActive ? Colors.white : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[index],
                      style: TextStyle(
                        fontSize: 10,
                        color: isActive ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isCompleted ? AppColors.primary : AppColors.disabled,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBasicInfoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _basicFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Basic Information',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter the basic details of your turf',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            
            _buildTextField(
              controller: _turfNameController,
              label: 'Turf Name',
              hint: 'Champions Arena',
              prefixIcon: Icons.stadium,
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _cityController,
              label: 'City',
              hint: 'Mumbai',
              prefixIcon: Icons.location_city,
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _addressController,
              label: 'Full Address',
              hint: '123, Sports Complex, Andheri West',
              prefixIcon: Icons.location_on,
              maxLines: 2,
              validator: (v) => v?.isEmpty == true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            
            _buildDropdown(),
            const SizedBox(height: 16),
            
            _buildTextField(
              controller: _descriptionController,
              label: 'Description (Optional)',
              hint: 'Premium turf with floodlights and covered seating...',
              prefixIcon: Icons.description,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _scheduleFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Schedule & Timing',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set your operating hours and slot duration',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            
            // Opening & Closing Time
            Row(
              children: [
                Expanded(
                  child: _buildTimePicker(
                    label: 'Opening Time',
                    time: _openTime,
                    onChanged: (time) => setState(() => _openTime = time),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTimePicker(
                    label: 'Closing Time',
                    time: _closeTime,
                    onChanged: (time) => setState(() => _closeTime = time),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Slot Duration
            const Text(
              'Slot Duration',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [30, 60, 90, 120].map((duration) {
                final isSelected = _slotDuration == duration;
                return ChoiceChip(
                  label: Text('$duration min'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _slotDuration = duration);
                  },
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            
            // Days Open
            const Text(
              'Days Open',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'
              ].map((day) {
                final isSelected = _selectedDays.contains(day);
                return FilterChip(
                  label: Text(day),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                    });
                  },
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPricingStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _pricingFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pricing Rules',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set different prices for day/night and weekday/weekend',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            
            // Night Start Time
            _buildTimePicker(
              label: 'Night Pricing Starts At',
              time: _nightStartTime,
              onChanged: (time) => setState(() => _nightStartTime = time),
            ),
            const SizedBox(height: 24),
            
            // Weekday Pricing
            _buildPricingSection(
              title: 'Weekday (Mon-Fri)',
              color: AppColors.primary,
              dayController: _weekdayDayPriceController,
              nightController: _weekdayNightPriceController,
            ),
            const SizedBox(height: 16),
            
            // Saturday Pricing
            _buildPricingSection(
              title: 'Saturday',
              color: AppColors.secondary,
              dayController: _saturdayDayPriceController,
              nightController: _saturdayNightPriceController,
            ),
            const SizedBox(height: 16),
            
            // Sunday Pricing
            _buildPricingSection(
              title: 'Sunday',
              color: AppColors.info,
              dayController: _sundayDayPriceController,
              nightController: _sundayNightPriceController,
            ),
            const SizedBox(height: 16),
            
            // Holiday Pricing
            _buildPricingSection(
              title: 'Public Holidays',
              color: AppColors.warning,
              dayController: _holidayDayPriceController,
              nightController: _holidayNightPriceController,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Turf Images',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add photos of your turf (optional for now)',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          
          // Add Images Button
          InkWell(
            onTap: _pickImages,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 48,
                    color: AppColors.primary.withOpacity(0.7),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap to add images',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Selected Images Grid
          if (_selectedImages.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(
                          image: FileImage(_selectedImages[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedImages.removeAt(index));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (index == 0)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Primary',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          
          const SizedBox(height: 24),
          
          // Tip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.infoLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: AppColors.info),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can add images later from turf settings. The first image will be used as the primary display image.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.info.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _previousStep,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Back'),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : (_currentStep == 3 ? _submitTurf : _nextStep),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_currentStep == 3 ? 'Submit for Review' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(prefixIcon, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Turf Type',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TurfType>(
              value: _selectedTurfType,
              isExpanded: true,
              items: TurfType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() => _selectedTurfType = value);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required Function(TimeOfDay) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (picked != null) onChanged(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Text(
                  time.format(context),
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPricingSection({
    required String title,
    required Color color,
    required TextEditingController dayController,
    required TextEditingController nightController,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded( 
                child: _buildPriceField(
                  label: 'Day Price',
                  controller: dayController,
                  icon: Icons.wb_sunny_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPriceField(
                  label: 'Night Price',
                  controller: nightController,
                  icon: Icons.nightlight_round,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) => v?.isEmpty == true ? 'Required' : null,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18),
            prefixText: '₹ ',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            filled: true,
            fillColor: AppColors.inputBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
