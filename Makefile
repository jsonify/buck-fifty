# Build and run Buck Fifty from the terminal; see Scripts/dist.sh for details.
.PHONY: dist run demo install test screenshots clean

dist:
	Scripts/dist.sh

run:
	Scripts/dist.sh --run

demo:
	Scripts/dist.sh --run --demo

install:
	Scripts/dist.sh --install

test:
	swift test --package-path Packages/ShoppingKit

screenshots:
	xcodegen generate --quiet
	Scripts/screenshots.sh

clean:
	rm -rf build dist screenshots
