#!/bin/sh
# Xcode Cloud: køres lige efter repoet er klonet.
# Projektet er beskrevet i project.yml (XcodeGen), og Mindebog.xcodeproj ligger ikke i git,
# så det genereres her, før Xcode Cloud bygger. Mappen ci_scripts skal ligge ved siden af
# Mindebog.xcodeproj (dvs. i ios/).
set -e

echo "Installerer XcodeGen"
brew install xcodegen

echo "Genererer Mindebog.xcodeproj"
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate

ls -la Mindebog.xcodeproj
