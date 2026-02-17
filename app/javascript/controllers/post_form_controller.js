import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "video"]

  onVideoSelected() {
    if (!this.hasTitleTarget || !this.hasVideoTarget) return
    if (this.titleTarget.value.trim().length > 0) return

    const selectedFile = this.videoTarget.files?.[0]
    if (!selectedFile) return

    this.titleTarget.value = this.suggestedTitle(selectedFile.name)
  }

  suggestedTitle(filename) {
    const baseName = filename.replace(/\.[^.]+$/, "")
    const normalized = baseName.replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim()
    if (normalized.length === 0) return ""

    return normalized[0].toUpperCase() + normalized.slice(1)
  }
}
