import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { Input } from "@ember/component";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import { isEmpty } from "@ember/utils";
import DsaModerationDetails from "discourse/components/dsa-moderation-details";
import ReviewableQueuedPost from "discourse/components/reviewable/queued-post";
import { popupAjaxError } from "discourse/lib/ajax-error";
import ComboBox from "discourse/select-kit/components/combo-box";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import DTextarea from "discourse/ui-kit/d-textarea";
import { i18n } from "discourse-i18n";

const OTHER_REASON = "other_reason";

export default class ReviseAndRejectPostReviewable extends Component {
  @service siteSettings;

  @tracked reason = OTHER_REASON;
  @tracked customReason;
  @tracked feedback;
  @tracked submitting = false;
  @tracked classificationStep = false;

  get configuredReasons() {
    const reasons = this.siteSettings.reviewable_revision_reasons
      .split("|")
      .filter(Boolean)
      .map((reason) => ({ id: reason, name: reason }))
      .concat([
        {
          id: OTHER_REASON,
          name: i18n("review.revise_and_reject_post.other_reason"),
        },
      ]);
    return reasons;
  }

  get showCustomReason() {
    return this.reason === OTHER_REASON;
  }

  get sendPMDisabled() {
    return (
      isEmpty(this.reason) ||
      (this.reason === OTHER_REASON && isEmpty(this.customReason)) ||
      this.submitting
    );
  }

  @action
  continueToClassification() {
    this.classificationStep = true;
  }

  @action
  backToAction() {
    this.classificationStep = false;
  }

  @action
  focusCurrentStep(element) {
    element.querySelector('[aria-current="step"]').focus();
  }

  @action
  async rejectAndSendPM(classification) {
    this.submitting = true;

    try {
      const data = {
        revise_reason: this.reason,
        revise_custom_reason: this.customReason,
        revise_feedback: this.feedback,
      };
      if (this.args.model.classificationOptions) {
        await this.args.model.perform({
          ...data,
          dsa_classification: classification,
        });
      } else {
        await this.args.model.performConfirmed(this.args.model.action, data);
      }
      this.args.closeModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.submitting = false;
    }
  }

  <template>
    <DModal
      class="revise-and-reject-reviewable"
      @closeModal={{@closeModal}}
      @title={{i18n "review.revise_and_reject_post.title"}}
    >
      <:body>
        {{#if @model.classificationOptions}}
          <ol
            aria-label={{i18n "review.moderation_steps.label"}}
            class="dsa-moderation-steps"
            {{didUpdate this.focusCurrentStep this.classificationStep}}
          >
            <li
              aria-current={{unless this.classificationStep "step"}}
              class={{if this.classificationStep "" "--current"}}
              tabindex="-1"
            >{{i18n "review.moderation_steps.action"}}</li>
            <li
              aria-current={{if this.classificationStep "step"}}
              class={{if this.classificationStep "--current"}}
              tabindex="-1"
            >{{i18n "dsa_statements.title"}}</li>
          </ol>
        {{/if}}
        <div hidden={{this.classificationStep}}>
          <div class="revise-and-reject-reviewable__queued-post">
            <ReviewableQueuedPost @reviewable={{@model.reviewable}} />
          </div>

          <div class="control-group">
            <label class="control-label" for="reason">{{i18n
                "review.revise_and_reject_post.reason"
              }}</label>
            <ComboBox
              class="revise-and-reject-reviewable__reason"
              @content={{this.configuredReasons}}
              @name="reason"
              @onChange={{fn (mut this.reason)}}
              @value={{this.reason}}
            />
          </div>

          {{#if this.showCustomReason}}
            <div class="control-group">
              <label class="control-label" for="custom_reason">{{i18n
                  "review.revise_and_reject_post.custom_reason"
                }}</label>
              <Input
                class="revise-and-reject-reviewable__custom-reason"
                name="custom_reason"
                @type="text"
                @value={{this.customReason}}
              />
            </div>
          {{/if}}

          <div class="control-group">
            <label class="control-label" for="feedback">{{i18n
                "review.revise_and_reject_post.feedback"
              }}
              <span class="revise-and-reject-reviewable__optional">({{i18n
                  "review.revise_and_reject_post.optional"
                }})</span>
            </label>
            <DTextarea
              class="revise-and-reject-reviewable__feedback"
              @name="feedback"
              @onChange={{fn (mut this.feedback)}}
              @value={{this.feedback}}
            />
          </div>
        </div>
        {{#if @model.classificationOptions}}
          <div hidden={{not this.classificationStep}}>
            <DsaModerationDetails
              @formId="revision-dsa-classification"
              @onSubmit={{this.rejectAndSendPM}}
              @options={{@model.classificationOptions}}
            />
          </div>
        {{/if}}
      </:body>
      <:footer>
        {{#if @model.classificationOptions}}
          {{#if this.classificationStep}}
            <DButton
              class="btn-primary"
              type="submit"
              @disabled={{this.submitting}}
              @form="revision-dsa-classification"
              @label="review.revise_and_reject_post.send_pm"
            />
            <DButton
              class="btn-flat"
              @action={{this.backToAction}}
              @disabled={{this.submitting}}
              @label="back_button"
            />
          {{else}}
            <DButton
              class="btn-primary"
              @action={{this.continueToClassification}}
              @disabled={{this.sendPMDisabled}}
              @label="continue"
            />
          {{/if}}
        {{else}}
          <DButton
            class="btn-primary"
            @action={{this.rejectAndSendPM}}
            @disabled={{this.sendPMDisabled}}
            @label="review.revise_and_reject_post.send_pm"
          />
          <DButton
            class="btn-flat d-modal-cancel"
            @action={{@closeModal}}
            @label="cancel"
          />
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
