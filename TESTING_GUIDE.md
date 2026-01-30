# Walking Navigation - Testing Guide

## Pre-Testing Checklist

- [ ] App builds successfully
- [ ] Device has location services enabled
- [ ] Maps permissions granted to Tiresias app
- [ ] Internet connection available (required for route calculation)
- [ ] Microphone permissions granted
- [ ] Device has sufficient storage for map data

---

## Test Case 1: Route Display on Mini Map

**Objective**: Verify blue route line appears on mini map when navigation starts

**Steps**:
1. Launch the app
2. Tap "Navigate" button
3. Say a nearby destination (e.g., "Central Park", "Times Square")
4. Wait 2-3 seconds for route calculation
5. Look at mini map in top-right corner

**Expected Results**:
- ✓ Blue polyline appears on mini map
- ✓ Destination marked with red pin
- ✓ Your location shown as blue dot
- ✓ "Route Ready" badge appears in top bar

**Pass/Fail**: _____

---

## Test Case 2: Expanded Map Route Visualization

**Objective**: Verify detailed route display in expanded map view

**Steps**:
1. Start navigation to a destination (see Test 1)
2. Ensure route is calculated (Route Ready badge visible)
3. Tap mini map to expand
4. Observe full-screen map display

**Expected Results**:
- ✓ Blue polyline shows complete walking path
- ✓ Red destination pin with label visible
- ✓ Your location shown with heading indicator
- ✓ Map style selector available (top-right)
- ✓ Re-center button available (bottom)
- ✓ Route statistics panel shows:
  - Distance in km or meters
  - Estimated time (minutes or hours:minutes)
  - Number of steps

**Pass/Fail**: _____

---

## Test Case 3: Route Information Panel

**Objective**: Verify route statistics are accurate and readable

**Steps**:
1. Open expanded map with active route
2. Check route info panel at bottom

**Expected Results**:
- ✓ Distance format matches route length (e.g., "0.5 km" or "450m")
- ✓ Time estimate reasonable for walking speed (~1.4 m/s)
- ✓ Step count matches turns in route (1+ for simple route)
- ✓ Text readable and high-contrast

**Examples**:
- 500m route → ~6 minutes, 1-2 steps ✓
- 2 km route → ~24 minutes, 4-8 steps ✓
- 5 km route → ~1h 5m, 8-15 steps ✓

**Pass/Fail**: _____

---

## Test Case 4: Multiple Destinations

**Objective**: Verify app handles different destination types

**Test 4A: Well-Known Location**
- Destination: "Central Park" or local major landmark
- Expected: Route calculated, polyline displayed

**Test 4B: Street Address**
- Destination: "Broadway and 42nd Street" or similar
- Expected: Route calculated, polyline displayed

**Test 4C: Neighborhood**
- Destination: "Times Square" or local district
- Expected: Route calculated, polyline displayed

**Test 4D: Invalid Destination**
- Destination: "xyz123abc" or obviously fake place
- Expected: Voice says "No results found" or similar
- Route NOT displayed

**Pass/Fail**: _____

---

## Test Case 5: Map Style Selector

**Objective**: Verify map style changes work

**Steps**:
1. Open expanded map with active route
2. Tap map style icon (top-right, rotates through Standard/Satellite/Hybrid)
3. Verify each style displays correctly

**Expected Results**:
- ✓ Standard map: Streets and labels visible
- ✓ Satellite map: Aerial imagery displayed
- ✓ Hybrid map: Satellite + street labels
- ✓ Blue route polyline visible in ALL styles
- ✓ Destination and user location visible in ALL styles

**Pass/Fail**: _____

---

## Test Case 6: Navigation Progress

**Objective**: Verify navigation updates in real-time

**Steps**:
1. Start navigation to destination
2. Walk a few steps (or simulate by changing location)
3. Watch mini map and distance counter
4. Verify voice announcements

**Expected Results**:
- ✓ Current distance to turn decreases as you move
- ✓ Voice announces turns when near waypoint
- ✓ "Distance to next turn" updates correctly
- ✓ Direction (left/right/straight) is accurate

**Pass/Fail**: _____

---

## Test Case 7: Stop Navigation

**Objective**: Verify cleanup when stopping navigation

**Steps**:
1. Start navigation to a destination
2. Route is displayed and "Route Ready" badge visible
3. Tap the Stop button (or X on navigation bar)
4. Observe maps

**Expected Results**:
- ✓ Blue route polyline disappears from maps
- ✓ Red destination pin disappears
- ✓ "Route Ready" badge disappears
- ✓ Mini map shows only your location + heading
- ✓ Voice announces "Navigation stopped"

**Pass/Fail**: _____

---

## Test Case 8: Accessibility Features

**Objective**: Verify accessibility announcements work

**Steps**:
1. Start navigation
2. Check with VoiceOver enabled (if available)
3. Expand map
4. Listen for announcements

**Expected Results**:
- ✓ "Route loaded" announced when route calculated
- ✓ Route distance/time announced clearly
- ✓ Map changes announced
- ✓ All buttons have accessibility labels
- ✓ Turn-by-turn instructions clear and concise

**Pass/Fail**: _____

---

## Test Case 9: Map Re-center Button

**Objective**: Verify re-center functionality

**Steps**:
1. Open expanded map with active route
2. Pan/drag map away from your location
3. Tap "Re-center" button
4. Observe camera movement

**Expected Results**:
- ✓ Map animates back to your location
- ✓ Smooth animation (0.5 second duration)
- ✓ Your location centered in view
- ✓ Heading direction respected in camera angle
- ✓ "Map centered on your location" announced

**Pass/Fail**: _____

---

## Test Case 10: Route Ready Badge

**Objective**: Verify status badge appears/disappears correctly

**Steps**:
1. Start app - no route active
2. Badge should NOT be visible
3. Start navigation to destination
4. Watch top bar
5. Stop navigation

**Expected Results**:
- ✓ Badge hidden when no route
- ✓ Badge appears when route calculated
- ✓ Green check mark visible
- ✓ Badge disappears when navigation stopped

**Pass/Fail**: _____

---

## Test Case 11: Long Route Display

**Objective**: Verify app handles long-distance routes

**Steps**:
1. Navigate to a distant location (3+ km away)
2. Open expanded map
3. Zoom out to see full route
4. Check if entire route visible and readable

**Expected Results**:
- ✓ Full route polyline visible on map
- ✓ Start and end points clear
- ✓ No visual artifacts or line breaks
- ✓ Distance/time estimates reasonable
- ✓ Map doesn't lag or freeze

**Pass/Fail**: _____

---

## Test Case 12: Mini Map Updates During Navigation

**Objective**: Verify mini map tracks your movement

**Steps**:
1. Start navigation
2. Wait for route to display on mini map
3. Move your location (physically walk or simulate)
4. Watch mini map

**Expected Results**:
- ✓ Your location marker (blue dot) updates
- ✓ Heading arrow rotates with your direction
- ✓ Updates smooth and frequent
- ✓ Route polyline remains stable

**Pass/Fail**: _____

---

## Performance Tests

### Test P1: Route Calculation Speed
- **Objective**: Route should calculate quickly
- **Test**: Time from voice input to blue route appearing
- **Pass Criteria**: < 5 seconds in normal conditions
- **Result**: _____

### Test P2: Map Rendering
- **Objective**: Maps should render smoothly
- **Test**: Expand/collapse map multiple times
- **Pass Criteria**: No lag, smooth animations
- **Result**: _____

### Test P3: Memory Usage
- **Objective**: App shouldn't leak memory
- **Test**: Multiple navigations (start/stop 5 times)
- **Pass Criteria**: App remains responsive
- **Result**: _____

---

## Bug Report Template

If issues found, document:

```
Bug #: ___
Title: _________________________________

Steps to Reproduce:
1. ____________________________________
2. ____________________________________
3. ____________________________________

Expected Result:
____________________________________

Actual Result:
____________________________________

Environment:
- iOS Version: __________
- Device: __________
- Location: __________
- Route Type: __________

Severity: [Critical] [High] [Medium] [Low]
```

---

## Edge Cases to Test

- [ ] Route from location with poor GPS signal
- [ ] Route to destination very close by (< 100m)
- [ ] Route to destination at extreme distance (> 30 km)
- [ ] Network disconnection during route calculation
- [ ] Location permissions granted mid-navigation
- [ ] Map expanded with no route active
- [ ] Multiple rapid destination changes
- [ ] Long-running navigation (1+ hour)
- [ ] Low battery mode enabled
- [ ] Dark mode enabled
- [ ] Split screen or picture-in-picture mode
- [ ] App backgrounded and foregrounded during navigation

---

## Success Criteria

Navigate successfully when:
- [ ] Blue route appears on both mini and expanded maps
- [ ] Route distance/time calculated correctly
- [ ] Voice navigation announces turns
- [ ] Maps update with your movement
- [ ] All controls responsive
- [ ] No crashes or errors in console

---

## Notes Section

Additional observations:
_________________________________________________________________

_________________________________________________________________

_________________________________________________________________

---

## Sign-Off

**Tested by**: ________________________  
**Date**: ________________________  
**Overall Status**: ☐ PASS  ☐ FAIL  

**Issues Found**: _____ (count)  
**Blockers**: _____ (count)  
**Ready for Release**: ☐ YES  ☐ NO
