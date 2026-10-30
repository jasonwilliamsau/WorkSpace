# XENEON EDGE touch setup

The touch driver routes physical XENEON EDGE input to the EDGE display even when the cursor begins on another screen.

## Permissions

The installed driver requires:

- **Input Monitoring** to read the touchscreen controller.
- **Accessibility** to synthesize pointer events.

macOS permission approval is intentionally manual. The installer does not attempt to bypass or automate system privacy controls.

## Cursor restoration

The driver's configuration controls whether the pointer returns to its pre-touch position after a completed gesture:

```json
{
  "cursor": {
    "returnToOriginalPositionAfterTouch": true
  }
}
```

Set the value to `false` to leave the pointer at the final EDGE touch position.

## Display identity

Display coordinates must never be hardcoded. The driver and dashboard resolve the selected display's current identity and bounds after launch, wake, and display-topology changes.

## Verification checklist

After installation, verify:

1. Tap routing when the cursor starts on another display.
2. Content scrolling with touch drag.
3. Window movement from title-bar drag.
4. Menu selection without immediate dismissal.
5. Cursor restoration according to the configured policy.
6. Recovery after sleep, wake, disconnect, and reconnect.
