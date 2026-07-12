class Swiftpico < Formula
  desc "Project and USB flashing tool for Swift Pico firmware"
  homepage "https://github.com/kyooni18/swiftpico"
  url "https://github.com/kyooni18/swiftpico/archive/refs/tags/v0.1.1.tar.gz"
  sha256 "e4a0ebc597c78d6ccdc3fce031119f8fd3abc2ddbed103763dd23a61f903a0b3"
  depends_on "picotool"
  depends_on xcode: :build

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "swiftpico"
    bin.install ".build/release/swiftpico"
  end

  test do
    assert_match "SwiftPico", shell_output("#{bin}/swiftpico help")
  end
end
