import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final  MapController _mapController = MapController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children:[
          FlutterMap(
            mapController: _mapController,
            options:const  MapOptions(
              initialCenter: LatLng(6.9271, 79.8612),
              initialZoom: 2,
              minZoom: 2,
              maxZoom: 100,
          ),
           children:[
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            CurrentLocationLayer(
              style: const LocationMarkerStyle(
                marker: DefaultLocationMarker(
                  child: Icon(
                    Icons.location_pin,
                    color: Colors.white,
                  ),
                ),
                markerSize: Size(40, 40),
                markerDirection: MarkerDirection.heading
              ),
            )
           ]
          ),
        ]
      ),
    );
  }
}
