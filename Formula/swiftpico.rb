class Swiftpico < Formula
  desc "Project and USB flashing tool for Swift Pico firmware"
  homepage "https://github.com/kyooni18/swiftpico"
  url "https://github.com/kyooni18/swiftpico/archive/refs/tags/v0.1.3.tar.gz"
  sha256 "0a8814656c8e637466f875c7aae049c9a291d418498c9f43ba76fca1ae7f6ae2"
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
