import { Controller } from "@hotwired/stimulus"

const GENERATED_INPUT_SELECTOR = 'input[data-profile-bulk-selection-generated="true"]'

export default class extends Controller {
  static targets = ["checkbox", "toggleButton", "bulkForm"]
  static values = { storageKey: String }

  connect() {
    this.selectedPostIds = new Set(this.loadSelectedPostIds())
    this.applySelectionToVisibleCheckboxes()
    this.renderHiddenInputs()
    this.syncButtonLabel()
  }

  selectAllPosts() {
    const shouldSelectAll = !this.anySelected()

    if (!shouldSelectAll) return this.clearSelection()

    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = true
      this.selectedPostIds.add(checkbox.value)
    })

    this.persistSelection()
    this.renderHiddenInputs()
    this.syncButtonLabel()
  }

  togglePostSelection(event) {
    const checkbox = event.currentTarget

    if (checkbox.checked) {
      this.selectedPostIds.add(checkbox.value)
    } else {
      this.selectedPostIds.delete(checkbox.value)
    }

    this.persistSelection()
    this.renderHiddenInputs()
    this.syncButtonLabel()
  }

  syncButtonLabel() {
    if (!this.hasToggleButtonTarget) return

    this.toggleButtonTarget.textContent = this.anySelected()
      ? "СНЯТЬ ВЫДЕЛЕНИЕ"
      : "ВЫДЕЛИТЬ ВСЕ ПОСТЫ"
  }

  anySelected() {
    return this.selectedPostIds.size > 0
  }

  clearSelection() {
    this.selectedPostIds.clear()

    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = false
    })

    this.persistSelection()
    this.renderHiddenInputs()
    this.syncButtonLabel()
  }

  applySelectionToVisibleCheckboxes() {
    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = this.selectedPostIds.has(checkbox.value)
    })
  }

  renderHiddenInputs() {
    if (!this.hasBulkFormTarget) return

    this.bulkFormTarget.querySelectorAll(GENERATED_INPUT_SELECTOR).forEach((input) => input.remove())

    const visiblePostIds = new Set(this.checkboxTargets.map((checkbox) => checkbox.value))
    this.selectedPostIds.forEach((postId) => {
      if (visiblePostIds.has(postId)) return

      const hiddenInput = document.createElement("input")
      hiddenInput.type = "hidden"
      hiddenInput.name = "post_ids[]"
      hiddenInput.value = postId
      hiddenInput.dataset.profileBulkSelectionGenerated = "true"
      this.bulkFormTarget.append(hiddenInput)
    })
  }

  loadSelectedPostIds() {
    if (!this.hasStorageKeyValue) return []

    try {
      const rawValue = sessionStorage.getItem(this.storageKeyValue)
      if (!rawValue) return []

      const parsedValue = JSON.parse(rawValue)
      if (!Array.isArray(parsedValue)) return []

      return parsedValue.map((id) => String(id)).filter((id) => id.length > 0)
    } catch (_error) {
      return []
    }
  }

  persistSelection() {
    if (!this.hasStorageKeyValue) return

    try {
      sessionStorage.setItem(this.storageKeyValue, JSON.stringify(Array.from(this.selectedPostIds)))
    } catch (_error) {
      // Ignore storage access errors in privacy mode.
    }
  }
}
