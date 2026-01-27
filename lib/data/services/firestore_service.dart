import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore Service
/// Handles all Firestore database operations
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get ownersCollection => _firestore.collection('owners');
  CollectionReference get turfsCollection => _firestore.collection('turfs');
  CollectionReference get slotsCollection => _firestore.collection('slots');
  CollectionReference get bookingsCollection => _firestore.collection('bookings');
  CollectionReference get playersCollection => _firestore.collection('players');

  // ==================== GENERIC OPERATIONS ====================

  /// Get a document by ID
  Future<DocumentSnapshot> getDocument(String collection, String docId) async {
    return await _firestore.collection(collection).doc(docId).get();
  }

  /// Create a document with auto-generated ID
  Future<DocumentReference> createDocument(
    String collection,
    Map<String, dynamic> data,
  ) async {
    return await _firestore.collection(collection).add(data);
  }

  /// Create a document with specific ID
  Future<void> setDocument(
    String collection,
    String docId,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    await _firestore.collection(collection).doc(docId).set(
      data,
      SetOptions(merge: merge),
    );
  }

  /// Update a document
  Future<void> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    await _firestore.collection(collection).doc(docId).update(data);
  }

  /// Delete a document
  Future<void> deleteDocument(String collection, String docId) async {
    await _firestore.collection(collection).doc(docId).delete();
  }

  // ==================== OWNER OPERATIONS ====================

  /// Get owner by ID
  Future<DocumentSnapshot> getOwner(String ownerId) async {
    return await ownersCollection.doc(ownerId).get();
  }

  /// Update owner profile
  Future<void> updateOwner(String ownerId, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await ownersCollection.doc(ownerId).update(data);
  }

  /// Check if owner exists by email or phone
  Future<bool> checkOwnerExists({String? email, String? phone}) async {
    if (email != null) {
      final emailQuery = await ownersCollection.where('email', isEqualTo: email).get();
      if (emailQuery.docs.isNotEmpty) return true;
    }
    
    if (phone != null) {
      final phoneQuery = await ownersCollection.where('phone', isEqualTo: phone).get();
      if (phoneQuery.docs.isNotEmpty) return true;
    }
    
    return false;
  }

  /// Get owner data by phone number
  Future<DocumentSnapshot?> getOwnerByPhone(String phone) async {
    final query = await ownersCollection.where('phone', isEqualTo: phone).limit(1).get();
    if (query.docs.isEmpty) return null;
    return query.docs.first;
  }

  // ==================== TURF OPERATIONS ====================

  /// Get turfs owned by a specific owner
  Stream<QuerySnapshot> getOwnerTurfs(String ownerId) {
    return turfsCollection
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get approved turfs only (for players)
  Stream<QuerySnapshot> getApprovedTurfs({String? city}) {
    Query query = turfsCollection.where('isApproved', isEqualTo: true);
    
    if (city != null && city.isNotEmpty) {
      query = query.where('city', isEqualTo: city);
    }
    
    return query.orderBy('createdAt', descending: true).snapshots();
  }

  /// Get single turf by ID
  Future<DocumentSnapshot> getTurf(String turfId) async {
    return await turfsCollection.doc(turfId).get();
  }

  /// Create a new turf
  Future<String> createTurf(Map<String, dynamic> data, {String? turfId}) async {
    data['createdAt'] = FieldValue.serverTimestamp();
    data['isApproved'] = false;
    data['verificationStatus'] = 'PENDING';
    
    if (turfId != null) {
      await turfsCollection.doc(turfId).set(data);
      return turfId;
    } else {
      final docRef = await turfsCollection.add(data);
      return docRef.id;
    }
  }

  /// Update turf
  Future<void> updateTurf(String turfId, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await turfsCollection.doc(turfId).update(data);
  }

  // ==================== SLOT OPERATIONS ====================

  /// Get slots for a turf on a specific date
  Stream<QuerySnapshot> getTurfSlots(String turfId, String date) {
    return slotsCollection
        .where('turfId', isEqualTo: turfId)
        .where('date', isEqualTo: date)
        .orderBy('startTime')
        .snapshots();
  }

  /// Get available slots for a turf on a specific date
  Stream<QuerySnapshot> getAvailableSlots(String turfId, String date) {
    return slotsCollection
        .where('turfId', isEqualTo: turfId)
        .where('date', isEqualTo: date)
        .where('status', isEqualTo: 'AVAILABLE')
        .orderBy('startTime')
        .snapshots();
  }

  /// Create or update slot
  Future<void> upsertSlot(String slotId, Map<String, dynamic> data) async {
    await slotsCollection.doc(slotId).set(data, SetOptions(merge: true));
  }

  /// Reserve a slot (with transaction for conflict prevention)
  Future<bool> reserveSlot(
    String slotId,
    String userId,
    Duration reservationDuration,
  ) async {
    try {
      return await _firestore.runTransaction<bool>((transaction) async {
        final slotDoc = await transaction.get(slotsCollection.doc(slotId));
        
        if (!slotDoc.exists) {
          throw 'Slot not found';
        }

        final data = slotDoc.data() as Map<String, dynamic>;
        final status = data['status'] as String;
        
        // Check if slot is available
        if (status == 'AVAILABLE') {
          // Reserve the slot
          transaction.update(slotsCollection.doc(slotId), {
            'status': 'RESERVED',
            'reservedBy': userId,
            'reservedUntil': Timestamp.fromDate(
              DateTime.now().add(reservationDuration),
            ),
          });
          return true;
        } else if (status == 'RESERVED') {
          // Check if reservation has expired
          final reservedUntil = (data['reservedUntil'] as Timestamp?)?.toDate();
          if (reservedUntil != null && DateTime.now().isAfter(reservedUntil)) {
            // Expired reservation, can reserve now
            transaction.update(slotsCollection.doc(slotId), {
              'status': 'RESERVED',
              'reservedBy': userId,
              'reservedUntil': Timestamp.fromDate(
                DateTime.now().add(reservationDuration),
              ),
            });
            return true;
          }
        }
        
        return false;
      });
    } catch (e) {
      print('Error reserving slot: $e');
      return false;
    }
  }

  /// Book a slot (confirm reservation)
  Future<void> bookSlot(String slotId) async {
    await slotsCollection.doc(slotId).update({
      'status': 'BOOKED',
      'reservedUntil': null,
    });
  }

  /// Release a slot (cancel reservation)
  Future<void> releaseSlot(String slotId) async {
    await slotsCollection.doc(slotId).update({
      'status': 'AVAILABLE',
      'reservedBy': null,
      'reservedUntil': null,
    });
  }

  /// Block a slot (by owner)
  Future<void> blockSlot(String slotId, String ownerId, String? reason) async {
    await slotsCollection.doc(slotId).update({
      'status': 'BLOCKED',
      'blockedBy': ownerId,
      'blockReason': reason,
    });
  }

  /// Unblock a slot
  Future<void> unblockSlot(String slotId) async {
    await slotsCollection.doc(slotId).update({
      'status': 'AVAILABLE',
      'blockedBy': null,
      'blockReason': null,
    });
  }

  // ==================== BOOKING OPERATIONS ====================

  /// Get bookings for owner's turfs
  Stream<QuerySnapshot> getOwnerBookings(String ownerId, List<String> turfIds) {
    if (turfIds.isEmpty) {
      return const Stream.empty();
    }
    
    return bookingsCollection
        .where('turfId', whereIn: turfIds)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get bookings for a specific turf
  Stream<QuerySnapshot> getTurfBookings(String turfId) {
    return bookingsCollection
        .where('turfId', isEqualTo: turfId)
        .orderBy('bookingDate', descending: true)
        .snapshots();
  }

  /// Get bookings for a specific date
  Stream<QuerySnapshot> getBookingsByDate(String turfId, String date) {
    return bookingsCollection
        .where('turfId', isEqualTo: turfId)
        .where('bookingDate', isEqualTo: date)
        .orderBy('startTime')
        .snapshots();
  }

  /// Get today's bookings for owner
  Future<QuerySnapshot> getTodaysBookings(List<String> turfIds) async {
    if (turfIds.isEmpty) {
      return await bookingsCollection.limit(0).get();
    }
    
    final today = DateTime.now().toIso8601String().split('T')[0];
    return await bookingsCollection
        .where('turfId', whereIn: turfIds)
        .where('bookingDate', isEqualTo: today)
        .where('bookingStatus', isEqualTo: 'CONFIRMED')
        .get();
  }

  /// Get pending payments (offline bookings)
  Future<QuerySnapshot> getPendingPayments(List<String> turfIds) async {
    if (turfIds.isEmpty) {
      return await bookingsCollection.limit(0).get();
    }
    
    return await bookingsCollection
        .where('turfId', whereIn: turfIds)
        .where('paymentStatus', isEqualTo: 'PAY_AT_TURF')
        .where('bookingStatus', isEqualTo: 'CONFIRMED')
        .get();
  }

  /// Create a booking
  Future<String> createBooking(Map<String, dynamic> data) async {
    data['createdAt'] = FieldValue.serverTimestamp();
    final docRef = await bookingsCollection.add(data);
    return docRef.id;
  }

  /// Update booking
  Future<void> updateBooking(String bookingId, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await bookingsCollection.doc(bookingId).update(data);
  }

  /// Cancel booking
  Future<void> cancelBooking(
    String bookingId,
    String cancelledBy,
    String? reason,
  ) async {
    await bookingsCollection.doc(bookingId).update({
      'bookingStatus': 'CANCELLED',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': cancelledBy,
      'cancellationReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Create atomic booking (slot + booking in single transaction)
  /// This prevents double-booking and ensures data consistency
  Future<String?> createAtomicBooking({
    required String slotId,
    required Map<String, dynamic> bookingData,
  }) async {
    try {
      return await _firestore.runTransaction<String?>((transaction) async {
        // 1. Read and verify the slot is available
        final slotDoc = await transaction.get(slotsCollection.doc(slotId));
        
        if (!slotDoc.exists) {
          throw Exception('Slot not found');
        }

        final slotData = slotDoc.data() as Map<String, dynamic>;
        final status = slotData['status'] as String;
        
        // Check if slot is available or has expired reservation
        if (status == 'BOOKED' || status == 'BLOCKED') {
          throw Exception('Slot is no longer available');
        }
        
        if (status == 'RESERVED') {
          final reservedUntil = slotData['reservedUntil'] as Timestamp?;
          if (reservedUntil != null && DateTime.now().isBefore(reservedUntil.toDate())) {
            throw Exception('Slot is currently reserved by another user');
          }
        }
        
        // 2. Mark slot as BOOKED atomically
        transaction.update(slotsCollection.doc(slotId), {
          'status': 'BOOKED',
          'reservedUntil': null,
          'reservedBy': null,
        });
        
        // 3. Create booking document atomically  
        final bookingRef = bookingsCollection.doc();
        transaction.set(bookingRef, {
          ...bookingData,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        return bookingRef.id;
      });
    } catch (e) {
      print('Atomic booking failed: $e');
      return null;
    }
  }

  /// Cancel booking with slot release (atomic operation)
  Future<bool> cancelBookingWithSlotRelease({
    required String bookingId,
    required String slotId,
    required String cancelledBy,
    String? reason,
  }) async {
    try {
      await _firestore.runTransaction((transaction) async {
        // 1. Verify booking exists and is not already cancelled
        final bookingDoc = await transaction.get(bookingsCollection.doc(bookingId));
        if (!bookingDoc.exists) {
          throw Exception('Booking not found');
        }
        
        final bookingData = bookingDoc.data() as Map<String, dynamic>;
        if (bookingData['bookingStatus'] == 'CANCELLED') {
          throw Exception('Booking is already cancelled');
        }
        
        // 2. Release the slot
        transaction.update(slotsCollection.doc(slotId), {
          'status': 'AVAILABLE',
          'reservedBy': null,
          'reservedUntil': null,
        });
        
        // 3. Mark booking as cancelled
        transaction.update(bookingsCollection.doc(bookingId), {
          'bookingStatus': 'CANCELLED',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': cancelledBy,
          'cancellationReason': reason,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      return true;
    } catch (e) {
      print('Cancel booking failed: $e');
      return false;
    }
  }

  // ==================== BATCH OPERATIONS ====================

  /// Batch create slots for a date
  Future<void> batchCreateSlots(List<Map<String, dynamic>> slots) async {
    final batch = _firestore.batch();
    
    for (final slotData in slots) {
      final docRef = slotsCollection.doc();
      batch.set(docRef, {
        ...slotData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    
    await batch.commit();
  }

  /// Check if slots exist for a date
  Future<bool> slotsExistForDate(String turfId, String date) async {
    final snapshot = await slotsCollection
        .where('turfId', isEqualTo: turfId)
        .where('date', isEqualTo: date)
        .limit(1)
        .get();
    
    return snapshot.docs.isNotEmpty;
  }
}
