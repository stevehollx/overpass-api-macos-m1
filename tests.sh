#!/bin/bash

echo "=== DATASET VERIFICATION TESTS ==="
echo "Checking what data is actually available in your Overpass database"
echo ""

# Test 1: Check if there's ANY highway data at all
echo "Test 1: Check for ANY highway data (no geography)"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];way[highway];out ids 10;'
echo -e "\n"

# Test 2: Check what's the bounding box of available data
echo "Test 2: Get bounding box of available data"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];way[highway];out ids bb 5;'
echo -e "\n"

# Test 3: Try major US cities that should definitely be in north-america-highways.osm.bz2
echo "Test 3a: New York City area (40.7128, -74.0060)"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];way[highway](around:5000,40.7128,-74.0060);out ids 5;'
echo -e "\n"

echo "Test 3b: Los Angeles area (34.0522, -118.2437)"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];way[highway](around:5000,34.0522,-118.2437);out ids 5;'
echo -e "\n"

echo "Test 3c: Denver area (39.7392, -104.9903) - closest major city to Boulder"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];way[highway](around:5000,39.7392,-104.9903);out ids 5;'
echo -e "\n"

# Test 4: Check what highway types are available
echo "Test 4: What highway types exist in the database?"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];way[highway];out tags 3;'
echo -e "\n"

# Test 5: Look for any ways with names (to see what areas are covered)
echo "Test 5: Ways with names (to identify coverage areas)"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];way[highway][name];out tags 5;'
echo -e "\n"

# Test 6: Try a very large bounding box to see if data exists anywhere
echo "Test 6: Large bounding box covering most of North America"
curl -X POST "http://localhost:12345/api/interpreter" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'data=[out:json][timeout:30];(way[highway](bbox:25,-125,50,-65););out ids 10;'
echo -e "\n"

echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "ANALYSIS:"
echo "- If Test 1 returns data: Database has highways, issue is geographic"
echo "- If Test 1 is empty: Database has no highway data at all"
echo "- Tests 3a-c will show which major cities have data"
echo "- Test 5 will show road names to identify covered areas"
echo "- Test 6 covers USA/Canada broadly"