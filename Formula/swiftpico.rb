class Swiftpico < Formula
  desc "Project and USB flashing tool for Swift Pico firmware"
  homepage "https://github.com/kyooni18/swiftpico"
  url "https://github.com/kyooni18/swiftpico/archive/refs/tags/v0.2.10.tar.gz"
  sha256 "REPLACE_AFTER_TAG_PUSH"
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
