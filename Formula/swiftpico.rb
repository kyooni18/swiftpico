class Swiftpico < Formula
  desc "Project and USB flashing tool for Swift Pico firmware"
  homepage "https://github.com/kyooni18/swiftpico"
  url "https://github.com/kyooni18/swiftpico/archive/refs/tags/v0.2.7.tar.gz"
  sha256 "4b8aa524989d4c103d96f8e42b59bc08e6790684894a887b97fd128c1f8f70d6"
  depends_on xcode: :build
  depends_on "picotool"

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "swiftpico"
    bin.install ".build/release/swiftpico"
  end

  test do
    assert_match "SwiftPico", shell_output("#{bin}/swiftpico help")
  end
end
