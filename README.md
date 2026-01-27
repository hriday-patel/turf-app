# Turf Booking App

A production-ready Flutter mobile app for booking Box Cricket / Turf slots.

## Features

### Owner System (Phase 1 - Complete)
- ✅ Owner Authentication (Login/Signup)
- ✅ Owner Dashboard with stats
- ✅ Add Turf with 6-tier pricing rules
- ✅ Turf Management with verification status
- ✅ Slot Generation & Management
- ✅ Booking Management
- ✅ Manual Booking (Phone/Walk-in)

### Player System (Phase 2 - Planned)
- 🔲 Player Authentication
- 🔲 Turf Discovery & Search
- 🔲 Slot Selection & Booking
- 🔲 Online/Offline Payment
- 🔲 Booking History

## Tech Stack

- **Frontend**: Flutter
- **Backend**: Firebase
  - Firebase Authentication
  - Cloud Firestore
  - Cloud Storage
- **State Management**: Provider
- **Payment**: Razorpay (abstracted)

## Getting Started

### Prerequisites
- Flutter SDK (>=3.0.0)
- Firebase CLI
- Android Studio / Xcode

### Setup

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd Turf-App
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   ```bash
   # Install FlutterFire CLI
   dart pub global activate flutterfire_cli
   
   # Configure Firebase
   flutterfire configure
   ```

4. **Update Firebase Options**
   - Replace placeholders in `lib/firebase_options.dart`
   - Add `google-services.json` (Android)
   - Add `GoogleService-Info.plist` (iOS)

5. **Deploy Firestore Rules**
   ```bash
   firebase deploy --only firestore:rules
   ```

6. **Run the app**
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── firebase_options.dart     # Firebase configuration
├── app/
│   ├── app.dart              # Main app widget
│   └── routes.dart           # App routes
├── config/
│   ├── colors.dart           # Color palette
│   └── theme.dart            # Theme configuration
├── core/
│   ├── constants/
│   │   ├── enums.dart        # All enums
│   │   └── strings.dart      # String constants
│   └── utils/
│       └── price_calculator.dart
├── data/
│   ├── models/               # Data models
│   └── services/             # Firebase services
└── features/
    ├── auth/                 # Authentication
    └── owner/                # Owner screens
```

## Pricing System

The app supports 6-tier pricing:
| Day Type | Time | Example Price |
|----------|------|---------------|
| Weekday | Day (6AM-6PM) | ₹1000/hr |
| Weekday | Night (6PM-11PM) | ₹1200/hr |
| Weekend | Day | ₹1400/hr |
| Weekend | Night | ₹1600/hr |
| Holiday | Day | ₹1800/hr |
| Holiday | Night | ₹2000/hr |

## Slot Booking Flow

1. User selects slot → Reserved (10 min timeout)
2. Chooses payment mode:
   - **Online**: Pay → Slot BOOKED
   - **Offline**: Slot BOOKED immediately (Pay at turf)
3. Owner can see all bookings and payment status

## Security

- Role-based access control via Firestore rules
- Owners can only access their own turfs
- Transaction-based slot reservation prevents double booking

## License

MIT License
