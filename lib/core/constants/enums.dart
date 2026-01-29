/// User roles in the application
enum UserRole {
  owner,
  player,
  admin,
}

/// Types of turf available
enum TurfType {
  boxCricket,
  groundCricket,
}

extension TurfTypeExtension on TurfType {
  String get displayName {
    switch (this) {
      case TurfType.boxCricket:
        return 'Box Cricket';
      case TurfType.groundCricket:
        return 'Ground Cricket';
    }
  }
  
  String get value {
    switch (this) {
      case TurfType.boxCricket:
        return 'BOX_CRICKET';
      case TurfType.groundCricket:
        return 'GROUND_CRICKET';
    }
  }
  
  static TurfType fromString(String value) {
    switch (value) {
      case 'BOX_CRICKET':
        return TurfType.boxCricket;
      case 'GROUND_CRICKET':
        return TurfType.groundCricket;
      // Legacy support
      case 'FOOTBALL':
      case 'MULTI_SPORT':
        return TurfType.boxCricket;
      default:
        return TurfType.boxCricket;
    }
  }
}

/// Turf operational status
enum TurfStatus {
  open,
  closed,
  renovation,
}

extension TurfStatusExtension on TurfStatus {
  String get displayName {
    switch (this) {
      case TurfStatus.open:
        return 'Open';
      case TurfStatus.closed:
        return 'Closed';
      case TurfStatus.renovation:
        return 'Under Renovation';
    }
  }
  
  String get value {
    switch (this) {
      case TurfStatus.open:
        return 'OPEN';
      case TurfStatus.closed:
        return 'CLOSED';
      case TurfStatus.renovation:
        return 'RENOVATION';
    }
  }
  
  static TurfStatus fromString(String value) {
    switch (value) {
      case 'CLOSED':
        return TurfStatus.closed;
      case 'RENOVATION':
        return TurfStatus.renovation;
      case 'ACTIVE':
      case 'OPEN':
      default:
        return TurfStatus.open;
    }
  }
}

/// Turf verification status
enum VerificationStatus {
  pending,
  approved,
  rejected,
}

extension VerificationStatusExtension on VerificationStatus {
  String get displayName {
    switch (this) {
      case VerificationStatus.pending:
        return 'Pending';
      case VerificationStatus.approved:
        return 'Approved';
      case VerificationStatus.rejected:
        return 'Rejected';
    }
  }
  
  String get value {
    switch (this) {
      case VerificationStatus.pending:
        return 'PENDING';
      case VerificationStatus.approved:
        return 'APPROVED';
      case VerificationStatus.rejected:
        return 'REJECTED';
    }
  }
  
  static VerificationStatus fromString(String value) {
    switch (value) {
      case 'APPROVED':
        return VerificationStatus.approved;
      case 'REJECTED':
        return VerificationStatus.rejected;
      default:
        return VerificationStatus.pending;
    }
  }
}

/// Slot status for availability tracking
enum SlotStatus {
  available,
  reserved,
  booked,
  blocked,
}

extension SlotStatusExtension on SlotStatus {
  String get displayName {
    switch (this) {
      case SlotStatus.available:
        return 'Available';
      case SlotStatus.reserved:
        return 'Reserved';
      case SlotStatus.booked:
        return 'Booked';
      case SlotStatus.blocked:
        return 'Blocked';
    }
  }
  
  String get value {
    switch (this) {
      case SlotStatus.available:
        return 'AVAILABLE';
      case SlotStatus.reserved:
        return 'RESERVED';
      case SlotStatus.booked:
        return 'BOOKED';
      case SlotStatus.blocked:
        return 'BLOCKED';
    }
  }
  
  static SlotStatus fromString(String value) {
    switch (value) {
      case 'RESERVED':
        return SlotStatus.reserved;
      case 'BOOKED':
        return SlotStatus.booked;
      case 'BLOCKED':
        return SlotStatus.blocked;
      default:
        return SlotStatus.available;
    }
  }
}

/// Source of booking
enum BookingSource {
  app,
  phone,
  walkIn,
}

extension BookingSourceExtension on BookingSource {
  String get displayName {
    switch (this) {
      case BookingSource.app:
        return 'App Booking';
      case BookingSource.phone:
        return 'Phone Booking';
      case BookingSource.walkIn:
        return 'Walk-In';
    }
  }
  
  String get value {
    switch (this) {
      case BookingSource.app:
        return 'APP';
      case BookingSource.phone:
        return 'PHONE';
      case BookingSource.walkIn:
        return 'WALK_IN';
    }
  }
  
  static BookingSource fromString(String value) {
    switch (value) {
      case 'PHONE':
        return BookingSource.phone;
      case 'WALK_IN':
        return BookingSource.walkIn;
      default:
        return BookingSource.app;
    }
  }
}

/// Payment mode selection
enum PaymentMode {
  online,
  offline,
}

extension PaymentModeExtension on PaymentMode {
  String get displayName {
    switch (this) {
      case PaymentMode.online:
        return 'Pay Online';
      case PaymentMode.offline:
        return 'Pay at Turf';
    }
  }
  
  String get value {
    switch (this) {
      case PaymentMode.online:
        return 'ONLINE';
      case PaymentMode.offline:
        return 'OFFLINE';
    }
  }
  
  static PaymentMode fromString(String value) {
    switch (value) {
      case 'ONLINE':
        return PaymentMode.online;
      default:
        return PaymentMode.offline;
    }
  }
}

/// Payment status tracking
enum PaymentStatus {
  paid,
  payAtTurf,
  pending,
  failed,
}

extension PaymentStatusExtension on PaymentStatus {
  String get displayName {
    switch (this) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.payAtTurf:
        return 'Pay at Turf';
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.failed:
        return 'Failed';
    }
  }
  
  String get value {
    switch (this) {
      case PaymentStatus.paid:
        return 'PAID';
      case PaymentStatus.payAtTurf:
        return 'PAY_AT_TURF';
      case PaymentStatus.pending:
        return 'PENDING';
      case PaymentStatus.failed:
        return 'FAILED';
    }
  }
  
  static PaymentStatus fromString(String value) {
    switch (value) {
      case 'PAID':
        return PaymentStatus.paid;
      case 'PAY_AT_TURF':
        return PaymentStatus.payAtTurf;
      case 'FAILED':
        return PaymentStatus.failed;
      default:
        return PaymentStatus.pending;
    }
  }
}

/// Booking status tracking
enum BookingStatus {
  confirmed,
  cancelled,
  completed,
  noShow,
}

extension BookingStatusExtension on BookingStatus {
  String get displayName {
    switch (this) {
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.cancelled:
        return 'Cancelled';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.noShow:
        return 'No Show';
    }
  }
  
  String get value {
    switch (this) {
      case BookingStatus.confirmed:
        return 'CONFIRMED';
      case BookingStatus.cancelled:
        return 'CANCELLED';
      case BookingStatus.completed:
        return 'COMPLETED';
      case BookingStatus.noShow:
        return 'NO_SHOW';
    }
  }
  
  static BookingStatus fromString(String value) {
    switch (value) {
      case 'CANCELLED':
        return BookingStatus.cancelled;
      case 'COMPLETED':
        return BookingStatus.completed;
      case 'NO_SHOW':
        return BookingStatus.noShow;
      default:
        return BookingStatus.confirmed;
    }
  }
}

/// Day type for pricing calculation
enum DayType {
  weekday,
  weekend,
  holiday,
}

extension DayTypeExtension on DayType {
  String get displayName {
    switch (this) {
      case DayType.weekday:
        return 'Weekday';
      case DayType.weekend:
        return 'Weekend';
      case DayType.holiday:
        return 'Holiday';
    }
  }
  
  String get value {
    switch (this) {
      case DayType.weekday:
        return 'WEEKDAY';
      case DayType.weekend:
        return 'WEEKEND';
      case DayType.holiday:
        return 'HOLIDAY';
    }
  }
  
  static DayType fromString(String value) {
    switch (value) {
      case 'WEEKEND':
      case 'SATURDAY':
      case 'SUNDAY':
        return DayType.weekend;
      case 'HOLIDAY':
        return DayType.holiday;
      default:
        return DayType.weekday;
    }
  }
}

/// Time type for pricing calculation
enum TimeType {
  day,
  night,
}

extension TimeTypeExtension on TimeType {
  String get displayName {
    switch (this) {
      case TimeType.day:
        return 'Day';
      case TimeType.night:
        return 'Night';
    }
  }
}

/// Image type for turf photos
enum TurfImageType {
  ground,
  nightLights,
  facility,
  other,
}

extension TurfImageTypeExtension on TurfImageType {
  String get displayName {
    switch (this) {
      case TurfImageType.ground:
        return 'Ground View';
      case TurfImageType.nightLights:
        return 'Night Lights';
      case TurfImageType.facility:
        return 'Facilities';
      case TurfImageType.other:
        return 'Other';
    }
  }
  
  String get value {
    switch (this) {
      case TurfImageType.ground:
        return 'GROUND';
      case TurfImageType.nightLights:
        return 'NIGHT_LIGHTS';
      case TurfImageType.facility:
        return 'FACILITY';
      case TurfImageType.other:
        return 'OTHER';
    }
  }
}

/// Days of the week
enum DayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

extension DayOfWeekExtension on DayOfWeek {
  String get shortName {
    switch (this) {
      case DayOfWeek.monday:
        return 'MON';
      case DayOfWeek.tuesday:
        return 'TUE';
      case DayOfWeek.wednesday:
        return 'WED';
      case DayOfWeek.thursday:
        return 'THU';
      case DayOfWeek.friday:
        return 'FRI';
      case DayOfWeek.saturday:
        return 'SAT';
      case DayOfWeek.sunday:
        return 'SUN';
    }
  }
  
  String get displayName {
    switch (this) {
      case DayOfWeek.monday:
        return 'Monday';
      case DayOfWeek.tuesday:
        return 'Tuesday';
      case DayOfWeek.wednesday:
        return 'Wednesday';
      case DayOfWeek.thursday:
        return 'Thursday';
      case DayOfWeek.friday:
        return 'Friday';
      case DayOfWeek.saturday:
        return 'Saturday';
      case DayOfWeek.sunday:
        return 'Sunday';
    }
  }
}
