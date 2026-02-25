import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "url",
    "title",
    "description",
    "status",
    "metadataButton",
    "downloadButton",
    "progress",
    "progressTrack",
    "progressFill",
    "progressText"
  ]
  static values = { metadataUrl: String }

  connect() {
    this.progressInterval = null
    this.progressValue = 0
    this.downloadButtonLabel = this.hasDownloadButtonTarget ? this.downloadButtonTarget.textContent.trim() : ""
  }

  disconnect() {
    this.clearProgressInterval()
  }

  async loadOptions() {
    if (!this.hasUrlTarget || !this.metadataUrlValue) return

    const url = this.urlTarget.value.trim()
    if (url.length === 0) {
      this.renderStatus("Вставьте ссылку YouTube.", "error")
      return
    }

    this.setMetadataLoading(true)
    this.renderStatus("Получаю метаданные...", "info")

    try {
      const response = await fetch(`${this.metadataUrlValue}?url=${encodeURIComponent(url)}`, {
        headers: { Accept: "application/json" }
      })
      const contentType = response.headers.get("content-type") || ""
      if (!contentType.includes("application/json")) {
        throw new Error("Сервер вернул неожиданный ответ. Обновите страницу и попробуйте снова.")
      }

      const payload = await response.json()
      if (!response.ok) {
        this.fillMetadata(payload)
        throw new Error(payload.error || "Не удалось получить данные YouTube.")
      }

      this.fillMetadata(payload)
      this.renderStatus("Название и описание подтянуты.", "ok")
    } catch (error) {
      this.renderStatus(error.message || "Ошибка при загрузке данных YouTube.", "error")
    } finally {
      this.setMetadataLoading(false)
    }
  }

  markDownloadRequested(event) {
    const url = this.hasUrlTarget ? this.urlTarget.value.trim() : ""
    if (url.length === 0) {
      event.preventDefault()
      this.renderStatus("Вставьте ссылку YouTube перед скачиванием.", "error")
      return
    }

  }

  onSubmitStart(event) {
    if (!this.shouldShowDownloadProgress(event)) return

    this.startProgress()
    this.renderStatus("Скачиваю видео через yt-dlp...", "info")
  }

  onSubmitEnd() {
    this.stopProgress()
  }

  shouldShowDownloadProgress(event) {
    if (!this.hasUrlTarget) return false
    if (this.urlTarget.value.trim().length === 0) return false

    const videoInput = this.element.querySelector('input[type="file"][name="post[video]"]')
    if (videoInput?.files?.length) return false

    return true
  }

  startProgress() {
    this.setDownloadLoading(true)
    this.progressValue = 6
    this.updateProgress()

    if (this.hasProgressTarget) this.progressTarget.hidden = false
    if (this.hasProgressTextTarget) this.progressTextTarget.textContent = "Скачивание началось..."

    this.clearProgressInterval()
    this.progressInterval = window.setInterval(() => {
      this.progressValue = Math.min(95, this.progressValue + 3)
      this.updateProgress()
      if (this.hasProgressTextTarget) this.progressTextTarget.textContent = `Скачивание... ${this.progressValue}%`
    }, 350)
  }

  stopProgress() {
    this.clearProgressInterval()
    this.setDownloadLoading(false)

    if (!this.hasProgressTarget) return

    this.progressValue = 100
    this.updateProgress()
    this.progressTarget.hidden = true
    if (this.hasProgressTextTarget) this.progressTextTarget.textContent = ""
  }

  clearProgressInterval() {
    if (!this.progressInterval) return

    window.clearInterval(this.progressInterval)
    this.progressInterval = null
  }

  updateProgress() {
    if (!this.hasProgressFillTarget || !this.hasProgressTrackTarget) return

    this.progressFillTarget.style.width = `${this.progressValue}%`
    this.progressTrackTarget.setAttribute("aria-valuenow", String(this.progressValue))
  }

  setMetadataLoading(isLoading) {
    if (this.hasMetadataButtonTarget) {
      this.metadataButtonTarget.disabled = isLoading
    }
  }

  setDownloadLoading(isLoading) {
    if (!this.hasDownloadButtonTarget) return

    this.downloadButtonTarget.disabled = isLoading
    this.downloadButtonTarget.textContent = isLoading ? "Скачиваю..." : this.downloadButtonLabel
  }

  fillMetadata(payload) {
    if (this.hasTitleTarget && this.titleTarget.value.trim().length === 0 && payload.title) {
      this.titleTarget.value = payload.title.toString().trim().slice(0, 120)
    }

    if (this.hasDescriptionTarget && this.descriptionTarget.value.trim().length === 0 && payload.description) {
      this.descriptionTarget.value = payload.description.toString().trim().slice(0, 5000)
    }
  }

  renderStatus(message, kind) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    this.statusTarget.classList.remove("youtube-import-status--error", "youtube-import-status--ok")
    if (kind === "error") this.statusTarget.classList.add("youtube-import-status--error")
    if (kind === "ok") this.statusTarget.classList.add("youtube-import-status--ok")
  }
}
