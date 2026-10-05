## Build and test

```sh
tuist install && tuist generate --no-open
tuist xcodebuild test -workspace Plunger.xcworkspace -scheme Plunger -destination 'platform=macOS' -only-testing:PlungerTests
tuist xcodebuild build -workspace Plunger.xcworkspace -scheme Plunger -destination 'platform=macOS'
```
