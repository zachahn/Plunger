## Build and test

```sh
xcodebuild test -project Plunger.xcodeproj -scheme Plunger -destination 'platform=macOS' -only-testing:PlungerTests
xcodebuild build -project Plunger.xcodeproj -scheme Plunger -destination 'platform=macOS'
```
