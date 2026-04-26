import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../config/colors.dart';
import '../../../config/glass_widgets.dart';
import '../../../core/constants/strings.dart';
import '../../../core/constants/enums.dart';
import '../../../app/routes.dart';
import '../../../data/models/turf_model.dart';
import '../../../data/services/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/turf_provider.dart';
import '../../../core/utils/app_toast.dart';

/// Multi-step form to create or edit a turf.
///
/// Steps (driven by [PageController]):
///   0. Basic info (name, city, address, type, nets, description)
///   1. Schedule (open/close time, slot duration, days open)
///   2. Pricing (per-net x per-day-type x per-time-slot)
///   3. Images (upload + manage existing)
///
/// Edit mode: when [editTurf] is provided, fields are pre-populated from the
/// existing turf, originals are tracked for change detection, and changes to
/// basic info trigger `verification_status='PENDING'` re-approval. Pricing,
/// schedule, and image edits do NOT trigger re-approval.
///
/// Renovation guard: if any net is under renovation, structural changes
/// (turf type, net count) are blocked with a dialog.
///
/// RouteAware: subscribes to `AppRoutes.routeObserver` so that returning
/// from a child screen can refresh provider state.
///
/// Image uploads happen inline in [_submitTurf] but turf creation does not
/// fail if image uploads fail — the user is informed via toast.
class AddTurfScreen extends StatefulWidget {
  final TurfModel? editTurf; // If provided, we're editing

  const AddTurfScreen({super.key, this.editTurf});

  @override
  State<AddTurfScreen> createState() => _AddTurfScreenState();
}

class _AddTurfScreenState extends State<AddTurfScreen> with RouteAware {
  static const Uuid _uuid = Uuid();
  // Default per-slot pricing (Indian market baseline). Used when creating a
  // new turf or when an existing turf has no per-slot price set.
  static const int _basePriceWeekday = 1000;
  static const int _basePriceWeekend = 1300;
  static const int _basePriceHoliday = 1500;
  static const double _eveningSurcharge = 1.2;
  static const double _nightSurcharge = 1.1;
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;
  bool get isEditing => widget.editTurf != null;

  // Track original basic info values to detect changes
  String? _originalTurfName;
  String? _originalCity;
  String? _originalAddress;
  TurfType? _originalTurfType;
  int? _originalNumberOfNets;
  String? _originalDescription;

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
  List<String> _selectedDays = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN'
  ];

  // Pricing Controllers - per net, per day type, per time slot
  List<Map<String, Map<String, TextEditingController>>> _netPricingControllers =
      [];

  // Time slots
  static const List<Map<String, String>> _timeSlots = [
    {'label': 'Morning', 'start': '06:00', 'end': '12:00'},
    {'label': 'Afternoon', 'start': '12:00', 'end': '18:00'},
    {'label': 'Evening', 'start': '18:00', 'end': '00:00'},
    {'label': 'Night', 'start': '00:00', 'end': '06:00'},
  ];

  static const List<String> _dayTypes = ['weekday', 'weekend', 'holiday'];
  static const List<String> _cityOptions = [
    'Ahmedabad',
    'Bengaluru',
    'Chennai',
    'Delhi',
    'Hyderabad',
    'Kolkata',
    'Mumbai',
    'Pune',
    'Surat',
  ];

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
    int basePrice = _basePriceWeekday;
    if (dayType == 'weekend') basePrice = _basePriceWeekend;
    if (dayType == 'holiday') basePrice = _basePriceHoliday;
    if (slotLabel == 'Evening')
      basePrice = (basePrice * _eveningSurcharge).round();
    if (slotLabel == 'Night') basePrice = (basePrice * _nightSurcharge).round();
    return basePrice;
  }

  void _populateFromTurf(TurfModel turf) {
    _turfNameController.text = turf.turfName;
    _cityController.text = turf.city;
    _addressController.text = turf.address;
    _descriptionController.text = turf.description ?? '';
    _selectedTurfType = turf.turfType;
    _numberOfNets = turf.numberOfNets;

    // Store original basic info values for change detection
    _originalTurfName = turf.turfName;
    _originalCity = turf.city;
    _originalAddress = turf.address;
    _originalTurfType = turf.turfType;
    _originalNumberOfNets = turf.numberOfNets;
    _originalDescription = turf.description ?? '';

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

    // Load existing images - filter out any invalid ones
    _existingImages = turf.images.where((img) => img.isValid).toList();

    // Initialize pricing controllers with existing values from turf
    _initializePricingControllersFromTurf(turf);
  }

  /// Check if basic info has changed (requires re-approval)
  bool _hasBasicInfoChanged() {
    if (!isEditing) return false;

    return _turfNameController.text.trim() != _originalTurfName ||
        _cityController.text.trim() != _originalCity ||
        _addressController.text.trim() != _originalAddress ||
        _selectedTurfType != _originalTurfType ||
        _numberOfNets != _originalNumberOfNets ||
        _descriptionController.text.trim() != _originalDescription;
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
    if (_currentStep == 1) {
      if (!_scheduleFormKey.currentState!.validate()) return;
      if (_selectedDays.isEmpty) {
        _showError(AppStrings.addTurfDaysOpenRequired);
        return;
      }
    }

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

  // U3: Image upload caps (must match server enforcement in api/storage/upload-image.js)
  static const int _maxImagesPerTurf = 10;
  static const int _maxImageBytes = 5 * 1024 * 1024; // 5 MB

  Future<void> _pickImages() async {
    try {
      final int currentTotal = _existingImages.length + _selectedImages.length;
      final int remainingSlots = _maxImagesPerTurf - currentTotal;
      if (currentTotal >= _maxImagesPerTurf) {
        _showError(
            '${AppStrings.addTurfImagesMaxReachedPrefix}$_maxImagesPerTurf${AppStrings.addTurfImagesMaxReachedSuffix}');
        return;
      }

      final List<XFile> images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (images.isEmpty) return;

      // Truncate to remaining slot count.
      final List<XFile> trimmed = images.length > remainingSlots
          ? images.sublist(0, remainingSlots)
          : images;

      // Reject any over the per-image size cap before adding.
      final List<XFile> accepted = [];
      int rejectedTooLarge = 0;
      for (final xf in trimmed) {
        final bytes = await xf.length();
        if (bytes > _maxImageBytes) {
          rejectedTooLarge++;
          continue;
        }
        accepted.add(xf);
      }

      if (accepted.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(accepted);
        });
      }

      if (images.length > remainingSlots) {
        _showError(
            '${AppStrings.addTurfImagesOnlyAllowedPrefix}$remainingSlots${AppStrings.addTurfImagesOnlyAllowedMid}$_maxImagesPerTurf${AppStrings.addTurfImagesOnlyAllowedSuffix}');
      } else if (rejectedTooLarge > 0) {
        _showError(
            '$rejectedTooLarge${AppStrings.addTurfImagesTooLargeSuffix}');
      }
    } catch (e) {
      _showError('${AppStrings.addTurfImagesPickFailedPrefix}$e');
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
            price:
                double.tryParse(controllers[dayType]!['Morning']!.text) ?? 1000,
          ),
          afternoon: TimeSlotPricing(
            label: 'Afternoon',
            startTime: '12:00',
            endTime: '18:00',
            price: double.tryParse(controllers[dayType]!['Afternoon']!.text) ??
                1000,
          ),
          evening: TimeSlotPricing(
            label: 'Evening',
            startTime: '18:00',
            endTime: '00:00',
            price:
                double.tryParse(controllers[dayType]!['Evening']!.text) ?? 1200,
          ),
          night: TimeSlotPricing(
            label: 'Night',
            startTime: '00:00',
            endTime: '06:00',
            price:
                double.tryParse(controllers[dayType]!['Night']!.text) ?? 1100,
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
    // U4: Prevent double-submit. Set flag synchronously before any async work.
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final turfProvider = Provider.of<TurfProvider>(context, listen: false);
      final storageService = StorageService();

      final openTimeStr =
          '${_openTime.hour.toString().padLeft(2, '0')}:${_openTime.minute.toString().padLeft(2, '0')}';
      final closeTimeStr =
          '${_closeTime.hour.toString().padLeft(2, '0')}:${_closeTime.minute.toString().padLeft(2, '0')}';

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
          final uploadResult =
              await storageService.uploadMultipleTurfImageBytesWithStatus(
            imageBytesList: imageBytesList,
            turfId: turfId,
          );

          // Check results
          if (uploadResult.allFailed) {
            imageUploadFailed = true;
            imageUploadMessage = kIsWeb
                ? AppStrings.addTurfUploadAllFailedWeb
                : AppStrings.addTurfUploadAllFailedNative;
          } else if (uploadResult.failedCount > 0) {
            imageUploadFailed = true;
            imageUploadMessage =
                '${uploadResult.successCount}${AppStrings.addTurfUploadPartialMid}${uploadResult.totalAttempted}${AppStrings.addTurfUploadPartialSuffix}';
          }

          turfImages = uploadResult.urls
              .asMap()
              .entries
              .map((entry) => TurfImage(
                    url: entry.value,
                    type: TurfImageType.ground,
                    // New images are only primary if there are no existing images
                    isPrimary: _existingImages.isEmpty && entry.key == 0,
                  ))
              .toList();
        } catch (e) {
          // Image upload failed, but continue with turf creation
          imageUploadFailed = true;
          imageUploadMessage = AppStrings.addTurfUploadGenericError;
        }
      }

      if (isEditing) {
        final currentTurf = widget.editTurf!;
        final hasNetsUnderRenovation =
            currentTurf.renovationNetNumbers.isNotEmpty;
        final isTurfTypeChanged = _selectedTurfType != currentTurf.turfType;
        final isNetCountChanged = _numberOfNets != currentTurf.numberOfNets;

        // Prevent structural changes while any net is under renovation.
        if (hasNetsUnderRenovation &&
            (isTurfTypeChanged || isNetCountChanged)) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text(AppStrings.addTurfStructuralBlockTitle),
              content: const Text(AppStrings.addTurfStructuralBlockMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(AppStrings.addTurfDialogOk),
                ),
              ],
            ),
          );
          return;
        }

        // Combine existing images with newly uploaded images
        // Filter out any invalid images and ensure proper primary flag
        final List<TurfImage> combinedImages = [
          ..._existingImages.where((img) => img.isValid),
          ...turfImages.where((img) => img.isValid),
        ];

        // Ensure at least one image is marked as primary (if any images exist)
        final List<Map<String, dynamic>> allImages;
        if (combinedImages.isNotEmpty) {
          final hasPrimary = combinedImages.any((img) => img.isPrimary);
          if (!hasPrimary) {
            // Mark the first image as primary
            allImages = combinedImages.asMap().entries.map((entry) {
              final img = entry.value;
              return {
                'url': img.url,
                'type': img.type.value,
                'isPrimary': entry.key == 0,
              };
            }).toList();
          } else {
            allImages = combinedImages.map((i) => i.toMap()).toList();
          }
        } else {
          allImages = [];
        }

        // Check if basic info changed - requires re-approval
        final basicInfoChanged = _hasBasicInfoChanged();

        // Build update data
        final updateData = {
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
          // Preserve renovation state across normal turf detail updates.
          'renovation_net_numbers': currentTurf.renovationNetNumbers,
          'images': allImages,
        };

        // If basic info changed, set status back to pending approval
        if (basicInfoChanged) {
          updateData['verification_status'] = 'PENDING';
          updateData['is_approved'] = false;
        }

        // Update existing turf
        final success = await turfProvider.updateTurf(turfId, updateData);

        if (!mounted) return;

        setState(() => _isLoading = false);

        if (success) {
          // Force refresh turfs from database to ensure UI is updated
          await turfProvider.refreshTurfs(authProvider.currentUserId!);

          if (!mounted) return;

          if (basicInfoChanged) {
            // If basic info changed, navigate to verification pending screen
            _showSuccess(AppStrings.addTurfUpdateSuccessReapproval);
            // Navigate to verification pending and clear navigation stack
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.verificationPending,
              (route) => route.isFirst,
            );
            return; // Don't continue to other navigation
          } else if (imageUploadFailed && _selectedImages.isNotEmpty) {
            _showSuccess(
                '${AppStrings.addTurfUpdateSuccessWithImagesPrefix}$imageUploadMessage');
          } else {
            _showSuccess(AppStrings.addTurfUpdateSuccess);
          }

          // Use Navigator.of with proper error handling
          if (Navigator.canPop(context)) {
            Navigator.pop(context, true);
          } else {
            Navigator.pushReplacementNamed(context, AppRoutes.myTurfs);
          }
        } else {
          _showError(
              turfProvider.errorMessage ?? AppStrings.addTurfUpdateFailed);
        }
      } else {
        // Create new turf - filter invalid images
        final validNewImages = turfImages.where((img) => img.isValid).toList();

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
          images: validNewImages,
        );

        if (!mounted) return;

        setState(() => _isLoading = false);

        if (resultId != null) {
          if (imageUploadFailed && _selectedImages.isNotEmpty) {
            _showSuccess('${AppStrings.turfAddedSuccess}! $imageUploadMessage');
          } else {
            _showSuccess(AppStrings.turfAddedSuccess);
          }
          Navigator.pushReplacementNamed(
              context, AppRoutes.verificationPending);
        } else {
          _showError(turfProvider.errorMessage ?? AppStrings.addTurfAddFailed);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(isEditing
          ? '${AppStrings.addTurfSubmitFailedUpdatePrefix}$e'
          : '${AppStrings.addTurfSubmitFailedAddPrefix}$e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppToast(context, message, type: ToastType.error);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    showAppToast(context, message, type: ToastType.success);
  }

  /// Refresh turf data in provider
  void _refreshTurfData() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final turfProvider = Provider.of<TurfProvider>(context, listen: false);
    if (authProvider.currentUserId != null) {
      turfProvider.loadOwnerTurfs(authProvider.currentUserId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Always refresh data when navigating back
          _refreshTurfData();
        }
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: GlassScaffoldBackground(
          child: SafeArea(
            child: Column(
              children: [
                GlassAppBar(
                  title: isEditing
                      ? AppStrings.addTurfEditTitle
                      : AppStrings.addTurfNewTitle,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back, color: c.textPrimary),
                    tooltip: AppStrings.addTurfBackTooltip,
                    onPressed: () {
                      _refreshTurfData();
                      Navigator.pop(context);
                    },
                  ),
                ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final c = AppColors.of(context);
    const steps = [
      AppStrings.addTurfStepBasicInfo,
      AppStrings.addTurfStepSchedule,
      AppStrings.addTurfStepPricing,
      AppStrings.addTurfStepImages,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: c.glassFill,
        border: Border(bottom: BorderSide(color: c.glassBorder)),
      ),
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
                        color: isActive ? c.primary : c.textDisabled,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isCompleted
                            ? Icon(Icons.check, color: c.onPrimary, size: 18)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color:
                                      isActive ? c.onPrimary : c.textSecondary,
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
                        color: isActive ? c.primary : c.textSecondary,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isCompleted ? c.primary : c.textDisabled,
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
    final c = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _basicFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.addTurfBasicInfoHeading,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.addTurfBasicInfoSubtitle,
              style: TextStyle(color: c.textSecondary),
            ),

            // Warning for edit mode
            if (isEditing) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: c.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.addTurfReapprovalNote,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.warning.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            _buildTextField(
              controller: _turfNameController,
              label: AppStrings.addTurfTurfNameLabel,
              hint: AppStrings.addTurfTurfNameHint,
              prefixIcon: Icons.stadium,
              maxLength: 60,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return AppStrings.addTurfFieldRequired;
                if (t.length > 60) {
                  return '${AppStrings.addTurfMaxCharsPrefix}60${AppStrings.addTurfMaxCharsSuffix}';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            _buildCityDropdown(),
            const SizedBox(height: 16),

            _buildTextField(
              controller: _addressController,
              label: AppStrings.addTurfAddressLabel,
              hint: AppStrings.addTurfAddressHint,
              prefixIcon: Icons.location_on,
              maxLines: 2,
              maxLength: 200,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return AppStrings.addTurfFieldRequired;
                if (t.length > 200) {
                  return '${AppStrings.addTurfMaxCharsPrefix}200${AppStrings.addTurfMaxCharsSuffix}';
                }
                return null;
              },
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
              label: AppStrings.addTurfDescriptionLabel,
              hint: AppStrings.addTurfDescriptionHint,
              prefixIcon: Icons.description,
              maxLines: 3,
              maxLength: 1000,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.length > 1000) {
                  return '${AppStrings.addTurfMaxCharsPrefix}1000${AppStrings.addTurfMaxCharsSuffix}';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetsSelector() {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.addTurfNetsLabel,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.textPrimary,
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
              selectedColor: c.primary,
              labelStyle: TextStyle(
                color: isSelected ? c.onPrimary : c.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.addTurfNetsHelp,
          style: TextStyle(fontSize: 12, color: c.textSecondary),
        ),
      ],
    );
  }

  Widget _buildDropdown() {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.addTurfTypeLabel,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: c.glassFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.glassBorder),
          ),
          child: DropdownButtonFormField<TurfType>(
            value: _selectedTurfType,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.sports_cricket, color: c.primary),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  Widget _buildCityDropdown() {
    final c = AppColors.of(context);
    final selectedCity = _cityOptions.contains(_cityController.text)
        ? _cityController.text
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.addTurfCityLabel,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedCity,
          validator: (value) => value == null || value.isEmpty
              ? AppStrings.addTurfFieldRequired
              : null,
          decoration: InputDecoration(
            hintText: AppStrings.addTurfCityHint,
            prefixIcon: Icon(Icons.location_city, color: c.primary),
            filled: true,
            fillColor: c.glassFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.primary, width: 2),
            ),
          ),
          items: _cityOptions
              .map(
                (city) => DropdownMenuItem<String>(
                  value: city,
                  child: Text(city),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _cityController.text = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildScheduleStep() {
    final c = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _scheduleFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.addTurfScheduleHeading,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.addTurfScheduleSubtitle,
              style: TextStyle(color: c.textSecondary),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildTimePicker(
                    label: AppStrings.addTurfOpeningTime,
                    time: _openTime,
                    onChanged: (time) => setState(() => _openTime = time),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTimePicker(
                    label: AppStrings.addTurfClosingTime,
                    time: _closeTime,
                    onChanged: (time) => setState(() => _closeTime = time),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.addTurfSlotDuration,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [60].map((duration) {
                final isSelected = _slotDuration == duration;
                return ChoiceChip(
                  label: Text('$duration min'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) setState(() => _slotDuration = duration);
                  },
                  selectedColor: c.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? c.onPrimary : c.textPrimary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.addTurfDaysOpen,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'].map((day) {
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
                  selectedColor: c.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? c.onPrimary : c.textPrimary,
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
    final c = AppColors.of(context);
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
                Text(
                  AppStrings.addTurfPricingHeading,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.addTurfPricingSubtitle,
                  style: TextStyle(color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (_numberOfNets > 1)
            Container(
              color: c.glassFill,
              child: TabBar(
                labelColor: c.primary,
                unselectedLabelColor: c.textSecondary,
                indicatorColor: c.primary,
                tabs: List.generate(
                    _numberOfNets,
                    (i) => Tab(
                        text: '${AppStrings.addTurfPricingNetPrefix}${i + 1}')),
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
    final c = AppColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildDayTypePricing(
              netIndex, 'weekday', AppStrings.addTurfWeekdaysTitle, c.primary),
          const SizedBox(height: 20),
          _buildDayTypePricing(netIndex, 'weekend',
              AppStrings.addTurfWeekendsTitle, c.secondary),
          const SizedBox(height: 20),
          _buildDayTypePricing(
              netIndex, 'holiday', AppStrings.addTurfHolidaysTitle, c.warning),
        ],
      ),
    );
  }

  Widget _buildDayTypePricing(
      int netIndex, String dayType, String title, Color color) {
    final c = AppColors.of(context);
    final controllers = _netPricingControllers[netIndex][dayType]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          '${slot['start']} - ${slot['end']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.textSecondary,
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
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      // U2: Hard price bounds — ₹50 min, ₹50,000 max per slot
                      validator: (v) {
                        final raw = v?.trim() ?? '';
                        if (raw.isEmpty) return AppStrings.addTurfFieldRequired;
                        final n = int.tryParse(raw);
                        if (n == null) return AppStrings.addTurfPriceInvalid;
                        if (n < 50) return AppStrings.addTurfPriceMin;
                        if (n > 50000) return AppStrings.addTurfPriceMax;
                        return null;
                      },
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
    final c = AppColors.of(context);
    final bool hasExistingImages = _existingImages.isNotEmpty;
    final bool hasNewImages = _selectedImages.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.addTurfImagesHeading,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.addTurfImagesSubtitle,
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 24),

          InkWell(
            onTap: _pickImages,
            borderRadius: BorderRadius.circular(16),
            child: Tooltip(
              message: AppStrings.addTurfImagesAddTooltip,
              child: Container(
                width: double.infinity,
                height: 150,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: c.primary.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 48,
                      color: c.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.addTurfImagesAddTap,
                      style: TextStyle(
                        color: c.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Show existing images from server (edit mode)
          if (hasExistingImages) ...[
            Text(
              '${AppStrings.addTurfImagesCurrentPrefix}${_existingImages.length}${AppStrings.addTurfImagesCountSuffix}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
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
                        color: c.textDisabled,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          image.url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          cacheWidth:
                              (MediaQuery.of(context).devicePixelRatio * 200)
                                  .round(),
                          gaplessPlayback: true,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: c.textDisabled,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: c.textSecondary,
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
                      child: Tooltip(
                        message: AppStrings.addTurfImagesRemoveTooltip,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _existingImages.removeAt(index));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
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
                    ),
                    if (image.isPrimary ||
                        (index == 0 &&
                            !_existingImages.any((i) => i.isPrimary)))
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            AppStrings.addTurfImagesPrimaryBadge,
                            style: TextStyle(
                              color: c.onPrimary,
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
              '${AppStrings.addTurfImagesNewPrefix}${_selectedImages.length}${AppStrings.addTurfImagesCountSuffix}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
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
                            color: c.textDisabled,
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
                      child: Tooltip(
                        message: AppStrings.addTurfImagesRemoveTooltip,
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _selectedImages.removeAt(index));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
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
                    ),
                    // Mark first new image as primary only if no existing images
                    if (index == 0 && _existingImages.isEmpty)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            AppStrings.addTurfImagesPrimaryBadge,
                            style: TextStyle(
                              color: c.onPrimary,
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
              color: c.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: c.info),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.addTurfImagesTip,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.info.withValues(alpha: 0.9),
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
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.glassFill,
        border: Border(top: BorderSide(color: c.glassBorder)),
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
                child: const Text(AppStrings.addTurfNavPrevious),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : (_currentStep < 3 ? _nextStep : _submitTurf),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.onPrimary,
                      ),
                    )
                  : Text(
                      _currentStep < 3
                          ? AppStrings.addTurfNavNext
                          : (isEditing
                              ? AppStrings.addTurfNavUpdate
                              : AppStrings.addTurfNavSubmit),
                      style: TextStyle(color: c.onPrimary),
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
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          inputFormatters: maxLength != null
              ? [LengthLimitingTextInputFormatter(maxLength)]
              : null,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(prefixIcon, color: c.primary),
            filled: true,
            fillColor: c.glassFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.primary, width: 2),
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
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: c.textPrimary,
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
              color: c.glassFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.glassBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: c.primary),
                const SizedBox(width: 12),
                Text(
                  time.format(context),
                  style: TextStyle(
                    fontSize: 16,
                    color: c.textPrimary,
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
