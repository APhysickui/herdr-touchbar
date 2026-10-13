.PHONY: check build run install preview
check:
	swift run --disable-sandbox HerdrCoreChecks
	swift build -c release --disable-sandbox
build:
	./scripts/build-app.sh
run: build
	open "dist/Herdr Touch Bar.app" --args --show
install:
	./scripts/install.sh
preview: build
	mkdir -p artifacts
	"dist/Herdr Touch Bar.app/Contents/MacOS/HerdrTouchBar" --render artifacts/dashboard-demo.png
