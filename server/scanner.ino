/*
  BLE Scanner for Arduino 101

  This sketch scans for nearby Bluetooth Low Energy (BLE) devices
  that are advertising. When a device with the specific local name
  "VuelingConnect" is discovered, it prints its MAC address,
  local name, and RSSI to the Serial Monitor. Other devices are ignored.

  Board: Arduino 101
  Library: CurieBLE (Included with Arduino 101 core)
*/

#include <CurieBLE.h>

// The specific local name we are looking for
const String TARGET_LOCAL_NAME = "VuelingConnect";

void setup() {
  // Initialize Serial communication at 9600 baud rate
  Serial.begin(9600);
  // Wait for Serial port to connect. Needed for native USB port only
  while (!Serial);

  Serial.println("Initializing BLE...");

  // Initialize the BLE hardware
  BLE.begin();

  Serial.println("BLE Initialized.");
  Serial.print("Starting BLE scan for '");
  Serial.print(TARGET_LOCAL_NAME);
  Serial.println("'...");

  // Start scanning for BLE peripherals.
  // scan() without arguments starts continuous scanning.
  BLE.scan();

  Serial.println("Scanning started. Waiting for matching peripherals...");
  Serial.println("-----------------------------------------");
}

void loop() {
  // Check if a new peripheral has been discovered
  // BLE.available() returns a BLEDevice object
  BLEDevice peripheral = BLE.available();

  // Check if a valid device was returned
  if (peripheral) {
    // Check if the peripheral has a local name AND if that name matches our target
    if (peripheral.hasLocalName() && peripheral.localName() == TARGET_LOCAL_NAME) { 
      // A matching peripheral was found!
      Serial.println("Matching Peripheral Discovered:");
      // Print the MAC address of the peripheral
      Serial.print("  Address: ");
      Serial.println(peripheral.address()); // Use address() method of BLEDevice
      
      // Print the Local Name (we already know it matches)
      Serial.print("  Local Name: ");
      Serial.println(peripheral.localName()); // Use localName() method of BLEDevice

      // Print the Received Signal Strength Indicator (RSSI)
      Serial.print("  RSSI: ");
      Serial.print(peripheral.rssi()); // Use rssi() method of BLEDevice
      Serial.println(" dBm");

      Serial.println("-----------------------------------------");
    }
  }
}