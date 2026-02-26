import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "toggleButton"]

  connect() {
    this.syncButtonLabel()
  }

  selectAllPosts() {
    const shouldSelectAll = !this.anySelected()

    this.checkboxTargets.forEach((checkbox) => {
      checkbox.checked = shouldSelectAll
    })

    this.syncButtonLabel()
  }

  syncButtonLabel() {
    if (!this.hasToggleButtonTarget) return

    this.toggleButtonTarget.textContent = this.anySelected()
      ? "СНЯТЬ ВЫДЕЛЕНИЕ"
      : "ВЫДЕЛИТЬ ВСЕ ПОСТЫ"
  }

  anySelected() {
    return this.checkboxTargets.some((checkbox) => checkbox.checked)
  }
}
