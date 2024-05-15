defmodule DisklavierWeb.Layouts.SwiftUI do
  use DisklavierNative, [:layout, format: :swiftui]

  embed_templates "layouts_swiftui/*"
end
