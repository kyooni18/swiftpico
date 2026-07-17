class Swiftpico < Formula
  desc "Project and USB flashing tool for Swift Pico firmware"
  homepage "https://github.com/kyooni18/swiftpico"
  url "https://github.com/kyooni18/swiftpico/archive/refs/tags/v0.2.16.tar.gz"
  sha256 "b6d975a619eb5cfc50d65a901d67c33f2d54be76f0d270fbdd4f30c3285bae9f"
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
