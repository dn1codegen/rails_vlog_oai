import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["title", "description", "video", "fetchButton", "status"]

  connect() {
    this.loading = false
  }

  onVideoSelected() {
    if (!this.hasTitleTarget || !this.hasVideoTarget) return
    if (this.titleTarget.value.trim().length > 0) return

    const selectedFile = this.videoTarget.files?.[0]
    if (!selectedFile) return

    this.titleTarget.value = this.suggestedTitle(selectedFile.name)
    this.setStatus("")
  }

  async fetchDescription(event) {
    event.preventDefault()
    if (this.loading) return

    const selectedFile = this.hasVideoTarget ? this.videoTarget.files?.[0] : null
    const title = this.hasTitleTarget ? this.titleTarget.value.trim() : ""

    if (!selectedFile && title.length === 0) {
      this.setStatus("Прикрепите видео или укажите название для поиска описания.", "error")
      return
    }

    const body = new FormData()
    if (selectedFile) body.append("video", selectedFile)
    if (title.length > 0) body.append("title", title)

    this.loading = true
    this.setButtonState(true)
    this.setStatus("Запрашиваю описание...", "")

    const headers = { Accept: "application/json" }
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    try {
      const response = await fetch("/posts/fetch_description", {
        method: "POST",
        headers,
        body
      })
      const payload = await response.json().catch(() => ({}))

      if (!response.ok || payload.status !== "ok") {
        const fallback = "Описание не найдено. Уточните название и попробуйте снова."
        this.setStatus(payload.message || fallback, "error")
        return
      }

      if (this.hasDescriptionTarget) {
        this.descriptionTarget.value = payload.description || ""
      }

      const source = payload.source ? `Источник: ${payload.source}.` : ""
      const order = Array.isArray(payload.source_order) && payload.source_order.length > 0 ?
        ` Порядок: ${payload.source_order.join(" -> ")}.` :
        ""
      this.setStatus(`Описание заполнено. ${source}${order}`.trim(), "ok")
    } catch (_error) {
      this.setStatus("Не удалось выполнить запрос. Проверьте сеть и попробуйте снова.", "error")
    } finally {
      this.loading = false
      this.setButtonState(false)
    }
  }

  suggestedTitle(filename) {
    const baseName = filename.replace(/\.[^.]+$/, "")
    const normalized = baseName.replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim()
    if (normalized.length === 0) return ""

    return normalized[0].toUpperCase() + normalized.slice(1)
  }

  setButtonState(disabled) {
    if (!this.hasFetchButtonTarget) return

    this.fetchButtonTarget.disabled = disabled
  }

  setStatus(message, kind = "") {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message || ""
    this.statusTarget.classList.remove("field-status--ok", "field-status--error")

    if (kind === "ok") {
      this.statusTarget.classList.add("field-status--ok")
    } else if (kind === "error") {
      this.statusTarget.classList.add("field-status--error")
    }
  }
}
