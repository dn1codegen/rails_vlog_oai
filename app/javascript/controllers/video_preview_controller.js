import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "player", "image"]
  static values = { frameUrls: Array }

  connect() {
    this.frameIndex = 0
    this.renderCurrentFrame()
  }

  selectFrame(event) {
    if (!this.hasImageTarget || !this.hasPreviewTarget || this.frameUrlsValue.length === 0) return

    const rect = this.previewTarget.getBoundingClientRect()
    if (rect.width <= 0) return

    const cursorX = Math.min(Math.max(event.clientX - rect.left, 0), rect.width - 1)
    const segmentWidth = rect.width / this.frameUrlsValue.length
    const nextIndex = Math.min(this.frameUrlsValue.length - 1, Math.floor(cursorX / segmentWidth))

    if (nextIndex === this.frameIndex) return

    this.frameIndex = nextIndex
    this.renderCurrentFrame()
  }

  resetPreview() {
    this.frameIndex = 0
    this.renderCurrentFrame()
  }

  play(event) {
    event.preventDefault()

    if (this.hasPreviewTarget) {
      this.previewTarget.classList.add("is-hidden")
    }

    if (this.hasPlayerTarget) {
      this.playerTarget.classList.remove("is-hidden")
      this.playerTarget.play().catch(() => {})
    }
  }

  renderCurrentFrame() {
    if (!this.hasImageTarget || this.frameUrlsValue.length === 0) return

    this.imageTarget.src = this.frameUrlsValue[this.frameIndex]
  }
}
