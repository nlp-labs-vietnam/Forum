import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DsaModerationDetails from "discourse/components/dsa-moderation-details";
import { extractError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";

export default class DsaModerationAction extends Component {
  @tracked flash;
  @tracked saving = false;

  get buttonClass() {
    return this.editing ? "btn-primary" : "btn-danger";
  }

  get buttonLabel() {
    return this.editing
      ? i18n("review.continue_to_editor")
      : this.args.model.action.label;
  }

  get editing() {
    return this.args.model.action.client_action === "edit";
  }

  @action
  async submit(classification) {
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.flash = null;
    try {
      await this.args.model.perform({ dsa_classification: classification });
      this.args.closeModal();
    } catch (error) {
      this.flash = extractError(error);
    } finally {
      this.saving = false;
    }
  }

  <template>
    <DModal
      class="dsa-moderation-action"
      ...attributes
      @closeModal={{@closeModal}}
      @dismissable={{not this.saving}}
      @flash={{this.flash}}
      @title={{@model.action.label}}
    >
      <:body>
        {{#if @model.action.confirm_message}}
          <p>{{@model.action.confirm_message}}</p>
        {{/if}}
        <h2 class="dsa-moderation-action__heading">{{i18n
            "dsa_statements.title"
          }}</h2>
        <DsaModerationDetails
          @formId="dsa-moderation-action-form"
          @onSubmit={{this.submit}}
          @options={{@model.options}}
        />
      </:body>
      <:footer>
        <DButton
          class={{this.buttonClass}}
          type="submit"
          @disabled={{this.saving}}
          @form="dsa-moderation-action-form"
          @isLoading={{this.saving}}
          @translatedLabel={{this.buttonLabel}}
        />
      </:footer>
    </DModal>
  </template>
}
