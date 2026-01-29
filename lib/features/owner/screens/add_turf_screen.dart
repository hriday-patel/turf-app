import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  final TurfModel? editTurf; // If provided, we're editing

  const AddTurfScreen({super.key, this.editTurf});

  @override
  State<AddTurfScreen> createState() => _AddTurfScreenState();
}

class _AddTurfScreenState extends State<AddTurfScreen> with RouteAware {
  final Uuid _uuid = const Uuid();
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool get isEditing => widget.editTurf != null;

  // Form Keys
  final _basicFormKey = GlobalKey<FormState>();
  final _scheduleFormKey = GlobalKey<FormState>();

  // Basic Info Controllers
  final _turfNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  TurfType _selectedTurfType = TurfType.boxCricket;
  int _numberOfNets = 1;

  // Schedule Controllers
  TimeOfDay _openTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _closeTime = const TimeOfDay(hour: 23, minute: 0);
  int _slotDuration = 60;
  List<String> _selectedDays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  // Pricing Controllers - per net, per day type, per time slot
  List<Map<String, Map<String, TextEditingController>>> _netPricingControllers = [];

  // Time slots
  static const List<Map<String, String>> _timeSlots = [
    {'label': 'Morning', 'start': '06:00', 'end': '12:00'},
    {'label': 'Afternoon', 'start': '12:00', 'end': '18:00'},
    {'label': 'Evening', 'start': '18:00', 'end': '00:00'},
    {'label': 'Night', 'start': '00:00', 'end': '06:00'},
  ];

  static const List<String> _dayTypes = ['weekday', 'weekend', 'holiday'];

  // Images - store as XFile for cross-platform support (new images)
  final List<XFile> _selectedImages = [];
  final ImagePicker _imagePicker = ImagePicker();
  
  // Existing images from server (for edit mode)
  List<TurfImage> _existingImages = [];

  @override
  void initState() {
    super.initState();
    _initializePricingControllers();
    if (isEditing) {
      _populateFromTurf(widget.editTurf!);
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppRoutes.routeObserver.subscribe(this, route);
    }
  }
  
  @override
  void didPopNext() {
    debugPrint('AddTurf: didPopNext - refreshing data if editing');
    if (isEditing && widget.editTurf != null) {
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.currentUserId != null) {
        turfProvider.loadOwnerTurfs(authProvider.currentUserId!);
      }
    }
  }

  void _initializePricingControllers() {
    // Dispose old controllers if any
    for (var netControllers in _netPricingControllers) {
      for (var dayControllers in netControllers.values) {
        for (var controller in dayControllers.values) {
          controller.dispose();
        }
      }
    }
    
    _netPricingControllers = List.generate(_numberOfNets, (netIndex) {
      return {
        for (var dayType in _dayTypes)
          dayType: {
            for (var slot in _timeSlots)
              slot['label']!: TextEditingController(
                text: _getDefaultPrice(dayType, slot['label']!).toString(),
              ),
          },
      };
    });
  }

  int _getDefaultPrice(String dayType, String slotLabel) {
    int basePrice = 1000;
    if (dayType == 'weekend') basePrice = 1300;
    if (dayType == 'holiday') basePrice = 1500;
    if (slotLabel == 'Evening') basePrice = (basePrice * 1.2).round();
    if (slotLabel == 'Night') basePrice = (basePrice * 1.1).round();
    return basePrice;
  }

  void _populateFromTurf(TurfModel turf) {
    _turfNameController.text = turf.turfName;
    _cityController.text = turf.city;
    _addressController.text = turf.address;
    _descriptionController.text = turf.description ?? '';
    _selectedTurfType = turf.turfType;
    _numberOfNets = turf.numberOfNets;
    
    final openParts = turf.openTime.split(':');
    _openTime = TimeOfDay(
      hour: int.parse(openParts[0]),
      minute: int.parse(openParts[1]),
    );
    
    final closeParts = turf.closeTime.split(':');
    _closeTime = TimeOfDay(
      hour: int.parse(closeParts[0]),
      minute: int.parse(closeParts[1]),
    );
    
    _slotDuration = turf.slotDurationMinutes;
    _selectedDays = List.from(turf.daysOpen);
    
    // Load existing images
    _existingImages = List.from(turf.images);
    
    // Initialize pricing controllers with existing values from turf
    _initializePricingControllersFromTurf(turf);
  }
  
  /// Initialize pricing controllers with values from existing turf
  void _initializePricingControllersFromTurf(TurfModel turf) {
    // Dispose old controllers if any
    for (var netControllers in _netPricingControllers) {
      for (var dayControllers in netControllers.values) {
        for (var controller in dayControllers.values) {
          controller.dispose();
        }
      }
    }
    
    _netPricingControllers = List.generate(_numberOfNets, (netIndex) {
      // Get pricing for this net from the turf's pricing rules
      final netPricing = turf.pricingRules.getNetPricing(netIndex + 1);
      
      return {
        'weekday': {
          'Morning': TextEditingController(
            text: netPricing?.weekday.morning.price.toInt().toString() ?? 
                  _getDefaultPrice('weekday', 'Morning').toString(),
          ),
          'Afternoon': TextEditingController(
            text: netPricing?.weekday.afternoon.price.toInt().toString() ?? 
                  _getDefaultPrice('weekday', 'Afternoon').toString(),
          ),
          'Evening': TextEditingController(
            text: netPricing?.weekday.evening.price.toInt().toString() ?? 
                  _getDefaultPrice('weekday', 'Evening').toString(),
          ),
          'Night': TextEditingController(
            text: netPricing?.weekday.night.price.toInt().toString() ?? 
                  _getDefaultPrice('weekday', 'Night').toString(),
          ),
        },
        'weekend': {
          'Morning': TextEditingController(
            text: netPricing?.weekend.morning.price.toInt().toString() ?? 
                  _getDefaultPrice('weekend', 'Morning').toString(),
          ),
          'Afternoon': TextEditingController(
            text: netPricing?.weekend.afternoon.price.toInt().toString() ?? 
                  _getDefaultPrice('weekend', 'Afternoon').toString(),
          ),
          'Evening': TextEditingController(
            text: netPricing?.weekend.evening.price.toInt().toString() ?? 
                  _getDefaultPrice('weekend', 'Evening').toString(),
          ),
          'Night': TextEditingController(
            text: netPricing?.weekend.night.price.toInt().toString() ?? 
                  _getDefaultPrice('weekend', 'Night').toString(),
          ),
        },
        'holiday': {
          'Morning': TextEditingController(
            text: netPricing?.holiday.morning.price.toInt().toString() ?? 
                  _getDefaultPrice('holiday', 'Morning').toString(),
          ),
          'Afternoon': TextEditingController(
            text: netPricing?.holiday.afternoon.price.toInt().toString() ?? 
                  _getDefaultPrice('holiday', 'Afternoon').toString(),
          ),
          'Evening': TextEditingController(
            text: netPricing?.holiday.evening.price.toInt().toString() ?? 
                  _getDefaultPrice('holiday', 'Evening').toString(),
          ),
          'Night': TextEditingController(
            text: netPricing?.holiday.night.price.toInt().toString() ?? 
                  _getDefaultPrice('holiday', 'Night').toString(),
          ),
        },
      };
    });
  }

  void _updateNumberOfNets(int newCount) {
    if (newCount == _numberOfNets) return;
    setState(() {
      _numberOfNets = newCount;
      _initializePricingControllers();
    });
  }

  @override
  void dispose() {
    AppRoutes.routeObserver.unsubscribe(this);
    _pageController.dispose();
    _turfNameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    for (var netControllers in _netPricingControllers) {
      for (var dayControllers in netControllers.values) {
        for (var controller in dayControllers.values) {
          controller.dispose();
        }
      }
    }
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0 && !_basicFormKey.currentState!.validate()) return;
    if (_currentStep == 1 && !_scheduleFormKey.currentState!.validate()) return;

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
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      _showError('Failed to pick images: $e');
    }
  }

  PricingRules _buildPricingRules() {
    List<NetPricing> netPricingList = [];
    
    for (int i = 0; i < _numberOfNets; i++) {
      final controllers = _netPricingControllers[i];
      
      DayTypePricing buildDayTypePricing(String dayType) {
        return DayTypePricing(
          morning: TimeSlotPricing(
            label: 'Morning',
            startTime: '06:00',
            endTime: '12:00',
            price: double.tryParse(controllers[dayType]!['Morning']!.text) ?? 1000,
          ),
          afternoon: TimeSlotPricing(
            label: 'Afternoon',
            startTime: '12:00',
            endTime: '18:00',
            price: double.tryParse(controllers[dayType]!['Afternoon']!.text) ?? 1000,
          ),
          evening: TimeSlotPricing(
            label: 'Evening',
            startTime: '18:00',
            endTime: '00:00',
            price: double.tryParse(controllers[dayType]!['Evening']!.text) ?? 1200,
          ),
          night: TimeSlotPricing(
            label: 'Night',
            startTime: '00:00',
            endTime: '06:00',
            price: double.tryParse(controllers[dayType]!['Night']!.text) ?? 1100,
          ),
        );
      }
      
      netPricingList.add(NetPricing(
        netNumber: i + 1,
        netName: 'Net ${i + 1}',
        weekday: buildDayTypePricing('weekday'),
        weekend: buildDayTypePricing('weekend'),
        holiday: buildDayTypePricing('holiday'),
      ));
    }
    
    return PricingRules(netPricing: netPricingList);
  }

  Future<void> _submitTurf() async {
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);
      final storageService = StorageService();

      final openTimeStr = '${_openTime.hour.toString().padLeft(2, '0')}:${_openTime.minute.toString().padLeft(2, '0')}';
      final closeTimeStr = '${_closeTime.hour.toString().padLeft(2, '0')}:${_closeTime.minute.toString().padLeft(2, '0')}';

      final pricingRules = _buildPricingRules();

      final turfId = isEditing ? widget.editTurf!.turfId : _uuid.v4();

      // Upload images (if any) - don't block turf creation on image upload failure
      List<TurfImage> turfImages = [];
      bool imageUploadFailed = false;
      String imageUploadMessage = '';
      
      if (_selectedImages.isNotEmpty) {
        try {
          // Convert XFile to bytes for web compatibility
          final List<Uint8List> imageBytesList = [];
          for (final xFile in _selectedImages) {
            final bytes = await xFile.readAsBytes();
            imageBytesList.add(bytes);
          }
          
          // Use the new method with status for better feedback
          final uploadResult = await storageService.uploadMultipleTurfImageBytesWithStatus(
            imageBytesList: imageBytesList,
            turfId: turfId,
          );
          
          // Check results
          if (uploadResult.allFailed) {
            imageUploadFailed = true;
            imageUploadMessage = kIsWeb 
                ? 'Image upload failed (network/CORS issue on web). Images not saved.'
                : 'All images failed to upload';
            debugPrint('All image uploads failed');
          } else if (uploadResult.failedCount > 0) {
            imageUploadFailed = true;
            imageUploadMessage = '${uploadResult.successCount}/${uploadResult.totalAttempted} images uploaded';
            debugPrint('Some images failed: ${uploadResult.successCount}/${uploadResult.totalAttempted}');
          }
          
          turfImages = uploadResult.urls.asMap().entries.map((entry) => TurfImage(
            url: entry.value,
            type: TurfImageType.ground,
            isPrimary: entry.key == 0,
          )).toList();
        } catch (e) {
          // Image upload failed, but continue with turf creation
          imageUploadFailed = true;
          imageUploadMessage = 'Image upload error';
          debugPrint('Image upload error: $e');
        }
      }

      if (isEditing) {
        // Combine existing images with newly uploaded images
        final List<Map<String, dynamic>> allImages = [
          ..._existingImages.map((i) => i.toMap()),
          ...turfImages.map((i) => i.toMap()),
        ];
        
        // Update existing turf
        final success = await turfProvider.updateTurf(turfId, {
          'turf_name': _turfNameController.text.trim(),
          'city': _cityController.text.trim(),
          'address': _addressController.text.trim(),
          'turf_type': _selectedTurfType.value,
          'description': _descriptionController.text.trim().isEmpty 
              ? null 
              : _descriptionController.text.trim(),
          'number_of_nets': _numberOfNets,
          'open_time': openTimeStr,
          'close_time': closeTimeStr,
          'slot_duration_minutes': _slotDuration,
          'days_open': _selectedDays,
          'pricing_rules': pricingRules.toMap(),
          'images': allImages,
        });

        setState(() => _isLoading = false);

        if (success && mounted) {
          // Force refresh turfs from database to ensure UI is updated
          await turfProvider.refreshTurfs(authProvider.currentUserId!);
          
          if (imageUploadFailed && _selectedImages.isNotEmpty) {
            _showSuccess('Turf updated! $imageUploadMessage');
          } else {
            _showSuccess('Turf updated successfully');
          }
          Navigator.pop(context, true);
        } else if (mounted) {
          _showError(turfProvider.errorMessage ?? 'Failed to update turf');
        }
      } else {
        // Create new turf
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
          numberOfNets: _numberOfNets,
          openTime: openTimeStr,
          closeTime: closeTimeStr,
          slotDurationMinutes: _slotDuration,
          daysOpen: _selectedDays,
          pricingRules: pricingRules,
          images: turfImages,
        );

        setState(() => _isLoading = false);

        if (resultId != null && mounted) {
          if (imageUploadFailed && _selectedImages.isNotEmpty) {
            _showSuccess('${AppStrings.turfAddedSuccess}! $imageUploadMessage');
          } else {
            _showSuccess(AppStrings.turfAddedSuccess);
          }
          Navigator.pushReplacementNamed(context, AppRoutes.verificationPending);
        } else if (mounted) {
          _showError(turfProvider.errorMessage ?? 'Failed to add turf');
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to ${isEditing ? 'update' : 'add'} turf: $e');
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
        title: Text(isEditing ? 'Edit Turf' : 'Add New Turf'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
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
            
            // Turf Type Dropdown
            _buildDropdown(),
            const SizedBox(height: 16),
            
            // Number of Nets
            _buildNetsSelector(),
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

  Widget _buildNetsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Number of Nets/Boxes',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: List.generate(6, (index) {
            final count = index + 1;
            final isSelected = _numberOfNets == count;
            return ChoiceChip(
              label: Text('$count'),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) _updateNumberOfNets(count);
              },
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          'Select how many nets or boxes are available at this turf',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonFormField<TurfType>(
            value: _selectedTurfType,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.sports_cricket, color: AppColors.primary),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: TurfType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Text(type.displayName),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedTurfType = value);
              }
            },
          ),
        ),
      ],
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
    return DefaultTabController(
      length: _numberOfNets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
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
                  'Set prices for each net across different time slots',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (_numberOfNets > 1)
            Container(
              color: Colors.white,
              child: TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: List.generate(_numberOfNets, (i) => Tab(text: 'Net ${i + 1}')),
              ),
            ),
          Expanded(
            child: TabBarView(
              children: List.generate(_numberOfNets, (netIndex) {
                return _buildNetPricingContent(netIndex);
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetPricingContent(int netIndex) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildDayTypePricing(netIndex, 'weekday', 'Weekdays (Mon-Fri)', AppColors.primary),
          const SizedBox(height: 20),
          _buildDayTypePricing(netIndex, 'weekend', 'Weekends (Sat-Sun)', AppColors.secondary),
          const SizedBox(height: 20),
          _buildDayTypePricing(netIndex, 'holiday', 'Public Holidays', AppColors.warning),
        ],
      ),
    );
  }

  Widget _buildDayTypePricing(int netIndex, String dayType, String title, Color color) {
    final controllers = _netPricingControllers[netIndex][dayType]!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(_timeSlots.length, (i) {
            final slot = _timeSlots[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slot['label']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${slot['start']} - ${slot['end']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: controllers[slot['label']!],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildImagesStep() {
    final int totalImages = _existingImages.length + _selectedImages.length;
    final bool hasExistingImages = _existingImages.isNotEmpty;
    final bool hasNewImages = _selectedImages.isNotEmpty;
    
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
          
          // Show existing images from server (edit mode)
          if (hasExistingImages) ...[
            Text(
              'Current Images (${_existingImages.length})',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _existingImages.length,
              itemBuilder: (context, index) {
                final image = _existingImages[index];
                return Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.disabled,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          image.url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.disabled,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _existingImages.removeAt(index));
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
                    if (image.isPrimary || (index == 0 && !_existingImages.any((i) => i.isPrimary)))
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            const SizedBox(height: 16),
          ],
          
          // Show newly selected images
          if (hasNewImages) ...[
            Text(
              'New Images (${_selectedImages.length})',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
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
                    FutureBuilder<Uint8List>(
                      future: _selectedImages[index].readAsBytes(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                image: MemoryImage(snapshot.data!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }
                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.disabled,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
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
                    // Mark first new image as primary only if no existing images
                    if (index == 0 && _existingImages.isEmpty)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          ],
          
          const SizedBox(height: 24),
          
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
                child: const Text('Previous'),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : (_currentStep < 3 ? _nextStep : _submitTurf),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _currentStep < 3
                          ? 'Next'
                          : (isEditing ? 'Update Turf' : 'Submit for Review'),
                      style: const TextStyle(color: Colors.white),
                    ),
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
            prefixIcon: Icon(prefixIcon, color: AppColors.primary),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
