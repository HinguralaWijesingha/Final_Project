import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:safe_pulse/db/db.dart';
import 'package:safe_pulse/model/contactdb.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final TextEditingController _locationController = TextEditingController();
  bool _isLoading = true;
  LatLng? _currentLocation;
  LatLng? _destinationLocation;
  List<LatLng> _route = [];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.sms,
    ].request();
  }

  Future<bool> _checkSmsPermission() async {
    if (!await Permission.sms.isGranted) {
      var status = await Permission.sms.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> _getCurrentLocation() async {
    if (!await _checkLocationPermission()) return;

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    if (!mounted) return;
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      _isLoading = false;
    });
  }

  Future<void> _getDestinationLocation(String location) async {
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$location&format=jsonv2&addressdetails=1');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data.isNotEmpty) {
        final lat = (data[0]['lat'] is String)
            ? double.parse(data[0]['lat'])
            : data[0]['lat'].toDouble();

        final lon = (data[0]['lon'] is String)
            ? double.parse(data[0]['lon'])
            : data[0]['lon'].toDouble();

        if (!mounted) return;
        setState(() {
          _destinationLocation = LatLng(lat, lon);
        });
        await _fetchRoute();
      } else {
        _showErrorMessage('Location not found');
      }
    } else {
      _showErrorMessage('Failed to fetch location data');
    }
  }

  Future<void> _fetchRoute() async {
    if (_currentLocation == null || _destinationLocation == null) return;

    final url = Uri.parse(
      "http://router.project-osrm.org/route/v1/driving/"
      '${_currentLocation!.longitude},${_currentLocation!.latitude};'
      '${_destinationLocation!.longitude},${_destinationLocation!.latitude}?overview=full&geometries=polyline',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final geometry = data['routes'][0]['geometry'];
      _decodePolyline(geometry);
    } else {
      _showErrorMessage('Failed to fetch route');
    }
  }

  void _decodePolyline(String encodedPolyline) {
    PolylinePoints polylinePoints = PolylinePoints();
    List<PointLatLng> decodedPoints =
        polylinePoints.decodePolyline(encodedPolyline);

    if (!mounted) return;
    setState(() {
      _route = decodedPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    });
  }

  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showErrorMessage('Location services are disabled.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showErrorMessage('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showErrorMessage('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  void _userCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15);
    } else {
      _showErrorMessage("Unable to get current location");
    }
  }

  void _goToDestination() async {
    if (_destinationLocation != null && _currentLocation != null) {
      _mapController.move(_currentLocation!, 15);
      await _fetchRoute();
    } else {
      _showErrorMessage("Please search for a destination first.");
    }
  }

  void _showErrorMessage(String? message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'Unknown error'),
      ),
    );
  }

  Future<void> _shareLocationWithContact() async {
    if (_currentLocation == null) {
      _showErrorMessage("Current location not available.");
      return;
    }

    final DB db = DB();
    final List<Dcontacts> emergencyContacts = await db.getContacts();

    if (!mounted) return;

    if (emergencyContacts.isEmpty) {
      _showErrorMessage("No emergency contacts found.");
      return;
    }

    Dcontacts? selectedContact;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Emergency Contact'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView(
              children: emergencyContacts
                  .map((contact) => ListTile(
                        title: Text(contact.name),
                        subtitle: Text(contact.number),
                        onTap: () {
                          selectedContact = contact;
                          Navigator.pop(context);
                        },
                      ))
                  .toList(),
            ),
          ),
        );
      },
    );

    if (selectedContact != null) {
      final String cleanNumber =
          selectedContact!.number.replaceAll(RegExp(r'\D'), '');

      final String message =
          "EMERGENCY! My current location: https://maps.google.com/?q=${_currentLocation!.latitude},${_currentLocation!.longitude}";

      try {
        // Check SMS permission first
        if (!await _checkSmsPermission()) {
          _showErrorMessage("SMS permission denied");
          return;
        }

        // Attempt direct send (Android only)
        String? result = await sendSMS(
          message: message,
          recipients: [cleanNumber],
          sendDirect: true,
        );

        if (result.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location shared successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // Fallback to normal SMS sending
          await sendSMS(
            message: message,
            recipients: [cleanNumber],
          );
        }
      } catch (error) {
        _showErrorMessage("Failed to send SMS: ${error.toString()}");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _currentLocation ?? const LatLng(6.9271, 79.8612),
                      initialZoom: 2,
                      minZoom: 0,
                      maxZoom: 100,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      ),
                      if (_currentLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentLocation!,
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_pin,
                                  color: Colors.red),
                            )
                          ],
                        ),
                      if (_destinationLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _destinationLocation!,
                              width: 40,
                              height: 40,
                              child:
                                  const Icon(Icons.flag, color: Colors.green),
                            )
                          ],
                        ),
                      if (_route.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _route,
                              strokeWidth: 4.0,
                              color: Colors.blue,
                            ),
                          ],
                        )
                    ],
                  ),
            Positioned(
              top: 0,
              right: 0,
              left: 0,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _locationController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Enter a location',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final location = _locationController.text.trim();
                      if (location.isNotEmpty) {
                        _getDestinationLocation(location);
                      }
                    },
                    icon: const Icon(Icons.search),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _shareLocationWithContact,
            label: const Text("Share"),
            icon: const Icon(Icons.share),
            backgroundColor: Colors.green,
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _userCurrentLocation,
            backgroundColor: Colors.blue,
            child: const Icon(
              Icons.my_location,
              size: 30,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            onPressed: _goToDestination,
            backgroundColor: Colors.deepPurple,
            tooltip: "Draw Directions",
            child: const Icon(
              Icons.directions,
              size: 30,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}