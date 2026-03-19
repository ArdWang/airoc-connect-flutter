/// Protocol constants for the Infineon AIROC OTA Upgrade BLE Service.
///
/// Reference: Infineon AIROC Connect Android/iOS bootloader v1 flow.
class AirocOtaConstants {
  AirocOtaConstants._();

  // ─────────────────────────────────────────────────────────────
  // Service / Characteristic UUIDs
  // ─────────────────────────────────────────────────────────────

  /// UUID of the AIROC OTA Upgrade Service.
  static const String otaServiceUuid =
      '';

  /// UUID of the OTA Control Point characteristic.
  ///
  /// Properties: Write, Notify.
  /// Used to issue commands and receive status notifications.p
  /// 11e4
  static const String otaCharacteristicUuid =
      '';

  // ─────────────────────────────────────────────────────────────
  // Packet framing
  // ─────────────────────────────────────────────────────────────

  /// Start byte of a packet.
  static const int packetStart = 0x01;

  /// End byte of a packet.
  static const int packetEnd = 0x17;

  /// Base size of packets sent to the bootloader (in bytes).
  static const int basePacketSize = 7;

  // ─────────────────────────────────────────────────────────────
  // Bootloader v1 commands
  // ─────────────────────────────────────────────────────────────

  /// Asks the device to verify the application image.
  static const int cmdVerifyApp = 0x31;

  /// Synchronizes the host and device.
  static const int cmdSync = 0x35;

  /// Sends data to the device.
  static const int cmdSendData = 0x37;

  /// Asks the device to enter the bootloader mode.
  static const int cmdEnterBootloader = 0x38;

  /// Programs one row (legacy bootloader command).
  static const int cmdProgramRow = 0x39;

  /// Exits the bootloader mode and starts the application.
  static const int cmdExitBootloader = 0x3B;

  /// Sends data to the device without expecting a response.
  static const int cmdSendDataWithoutResponse = 0x47;

  /// Programs the received data into the device's memory.
  static const int cmdProgramData = 0x49;

  /// Verifies the programmed data in the device's memory.
  static const int cmdVerifyData = 0x4A;

  /// Sets metadata for the application image.
  static const int cmdSetAppMetadata = 0x4C;

  /// Sets the Encryption Initialization Vector.
  static const int cmdSetEiv = 0x4D;

  // ─────────────────────────────────────────────────────────────
  // Response layout
  // ─────────────────────────────────────────────────────────────

  /// Byte offset for the status in the response.
  static const int responseStatusOffset = 1;

  /// Byte offset for the length in the response.
  static const int responseLengthOffset = 2;

  /// Byte offset for the data in the response.
  static const int responseDataOffset = 4;

  // ─────────────────────────────────────────────────────────────
  // Bootloader status codes
  // ─────────────────────────────────────────────────────────────

  /// Command / operation succeeded.
  static const int statusSuccess = 0x00;

  /// Error: Invalid firmware file.
  static const int statusErrFile = 0x01;

  /// Error: Unexpected end of firmware file.
  static const int statusErrEof = 0x02;

  /// Error: Firmware file has an invalid length.
  static const int statusErrLength = 0x03;

  /// Error: Invalid data received.
  static const int statusErrData = 0x04;

  /// Error: Unrecognized command.
  static const int statusErrCommand = 0x05;

  /// Error: Device error.
  static const int statusErrDevice = 0x06;

  /// Error: Firmware version mismatch.
  static const int statusErrVersion = 0x07;

  /// Error: Checksum mismatch.
  static const int statusErrChecksum = 0x08;

  /// Error: Invalid array address.
  static const int statusErrArray = 0x09;

  /// Error: Invalid row address.
  static const int statusErrRow = 0x0A;

  /// Status: Bootloader is active.
  static const int statusBootloader = 0x0B;

  /// Error: Application image is invalid.
  static const int statusErrApp = 0x0C;

  /// Error: Application is not active.
  static const int statusErrActive = 0x0D;

  /// Error: Unknown error.
  static const int statusErrUnknown = 0x0E;

  /// Operation aborted.
  static const int statusAbort = 0x0F;

  // ─────────────────────────────────────────────────────────────
  // Checksum algorithms
  // ─────────────────────────────────────────────────────────────

  /// Sum checksum algorithm identifier.
  static const int sumChecksum = 0x00;

  /// CRC checksum algorithm identifier.
  static const int crcChecksum = 0x01;

  // ─────────────────────────────────────────────────────────────
  // Transfer Parameters
  // ─────────────────────────────────────────────────────────────

  /// Requested MTU size; actual MTU is negotiated by the stack.
  static const int requestedMtu = 512;

  /// Fallback chunk size when MTU negotiation is unavailable.
  static const int defaultChunkSize = 133;

  /// Chunk size for writes without response.
  static const int writeWithoutResponseChunkSize = 300;

  /// Delay between successive data writes to avoid GATT congestion.
  static const Duration writePacing = Duration(milliseconds: 5);
  /// Number of extra VERIFY_APP retries when device returns CYRET_ERR_DATA.
  static const int verifyAppRetryCount = 2;

  /// Delay between VERIFY_APP retries.
  static const Duration verifyAppRetryDelay = Duration(milliseconds: 120);

  // ─────────────────────────────────────────────────────────────
  // Time-outs
  // ─────────────────────────────────────────────────────────────

  /// Maximum time to wait for a control-point response notification.
  static const Duration controlPointTimeout = Duration(seconds: 30);

  /// Maximum time allowed for the full firmware transfer.
  static const Duration transferTimeout = Duration(minutes: 5);

  /// Maximum time to wait for a connection to be established.
  static const Duration connectTimeout = Duration(seconds: 15);

  // ─────────────────────────────────────────────────────────────
  // File Format
  // ─────────────────────────────────────────────────────────────

  /// File extension for Cypress Application Code And Data v2 files.
  static const String cyacd2Extension = '.cyacd2';

  /// File extension for legacy Cypress Application Code And Data files.
  static const String cyacdExtension = '.cyacd';

  /// Supported firmware extensions accepted by file picker.
  static const List<String> supportedFirmwareExtensions = <String>[
    'cyacd2',
    'cyacd',
  ];

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  /// Returns a human-readable description for [statusCode].
  static String statusMessage(int statusCode) {
    switch (statusCode) {
      case statusSuccess:
        return 'Success';
      case statusErrFile:
        return 'CYRET_ERR_FILE';
      case statusErrEof:
        return 'CYRET_ERR_EOF';
      case statusErrLength:
        return 'CYRET_ERR_LENGTH';
      case statusErrData:
        return 'CYRET_ERR_DATA';
      case statusErrCommand:
        return 'CYRET_ERR_CMD';
      case statusErrDevice:
        return 'CYRET_ERR_DEVICE';
      case statusErrVersion:
        return 'CYRET_ERR_VERSION';
      case statusErrChecksum:
        return 'CYRET_ERR_CHECKSUM';
      case statusErrArray:
        return 'CYRET_ERR_ARRAY';
      case statusErrRow:
        return 'CYRET_ERR_ROW';
      case statusBootloader:
        return 'CYRET_BTLDR';
      case statusErrApp:
        return 'CYRET_ERR_APP';
      case statusErrActive:
        return 'CYRET_ERR_ACTIVE';
      case statusErrUnknown:
        return 'CYRET_ERR_UNK';
      case statusAbort:
        return 'CYRET_ABORT';
      default:
        return 'Unknown (0x${statusCode.toRadixString(16).padLeft(2, '0')})';
    }
  }
}
