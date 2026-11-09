import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/models/car_record_model.dart';

class LocationDetails {
  final double latitude;
  final double longitude;
  final String district;
  final String street;
  final String gpsUrl;

  const LocationDetails({
    required this.latitude,
    required this.longitude,
    required this.district,
    required this.street,
    required this.gpsUrl,
  });
}

class LocationService {
  static final LocationService instance = LocationService._init();
  LocationService._init();

  /// Determine the current position of the device and reverse geocode it
  Future<LocationDetails?> getCurrentLocationDetails() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return _fallbackLocation();
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return _fallbackLocation();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        return _fallbackLocation();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      String district = 'غير محدد';
      String street = 'غير محدد';

      try {
        final placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          district = place.subLocality?.isNotEmpty == true
              ? place.subLocality!
              : (place.locality?.isNotEmpty == true
                  ? place.locality!
                  : (place.administrativeArea ?? 'غير محدد'));

          street = place.thoroughfare?.isNotEmpty == true
              ? place.thoroughfare!
              : (place.street?.isNotEmpty == true ? place.street! : 'غير محدد');
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
      }

      final gpsUrl = CarRecord.buildGpsUrl(position.latitude, position.longitude);

      return LocationDetails(
        latitude: position.latitude,
        longitude: position.longitude,
        district: district,
        street: street,
        gpsUrl: gpsUrl,
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return _fallbackLocation();
    }
  }

  LocationDetails _fallbackLocation() {
    const lat = 24.7136; // Default fallback (e.g. Riyadh)
    const lng = 46.6753;
    return LocationDetails(
      latitude: lat,
      longitude: lng,
      district: 'حي الملقا',
      street: 'طريق الملك فهد',
      gpsUrl: CarRecord.buildGpsUrl(lat, lng),
    );
  }
}
