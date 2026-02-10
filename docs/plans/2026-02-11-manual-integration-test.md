# SpeakSmooth Manual Integration Test

Date: 2026-02-11

## Environment check

- Build succeeded: `xcodebuild -project SpeakSmooth.xcodeproj -scheme SpeakSmooth build -quiet`
- Tests succeeded: `xcodebuild test -project SpeakSmooth.xcodeproj -scheme SpeakSmooth -destination 'platform=macOS' -quiet`
- App launch sanity check succeeded: `open` + process observed, then terminated

## Interactive checklist

These checks require local interactive UI, microphone input, and Microsoft account sign-in.

1. Mic permission prompt appears on first launch.
2. Menu bar icon appears in idle state and popover opens.
3. Start keeps recording active even when popover closes.
4. Speaking moves status to "Hearing you...".
5. Silence timeout triggers STT -> Rewrite -> Save states.
6. Settings allows Microsoft sign in and list selection.
7. Full pipeline creates task in selected Microsoft To Do list.
8. Stop returns icon/state to idle.
9. Network-off path shows recoverable error and auto-dismisses.

## Notes

- `MSALClientId` is now read from `Info.plist` (`MSALClientId` key) and must be set for sign-in.
