/* eslint-disable ember/no-tracked-properties-from-args */
import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { isEmpty } from "@ember/utils";
import AdminPenaltyPostAction from "discourse/admin/components/admin-penalty-post-action";
import AdminPenaltyReason from "discourse/admin/components/admin-penalty-reason";
import AdminPenaltySimilarUsers from "discourse/admin/components/admin-penalty-similar-users";
import DsaModerationDetails from "discourse/components/dsa-moderation-details";
import { extractError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import DFutureDateInput from "discourse/ui-kit/d-future-date-input";
import DModal from "discourse/ui-kit/d-modal";
import I18n, { i18n } from "discourse-i18n";

export default class PenalizeUser extends Component {
  @service dialog;
  @service siteSettings;

  @tracked penalizeUntil = this.args.model.user.next_penalty;
  @tracked penalizing = false;
  @tracked confirmClose = false;

  @tracked otherUserIds = [];
  @tracked postAction = this.args.model.postId ? "delete" : "none";
  @tracked postEdit = this.args.model.postEdit;
  @tracked flash;
  @tracked reason;
  @tracked message;
  @tracked readyToDeleteAll = false;
  @tracked classificationStep = false;
  #beforeCompleted = false;

  constructor() {
    super(...arguments);
    if (this.postEdit && this.siteSettings.penalty_include_post_message) {
      this.message = `-------------------\n${this.postEdit}\n-------------------`;
    }
  }

  get modalTitle() {
    if (this.args.model.penaltyType === "suspend") {
      return "admin.user.suspend_modal_title";
    } else if (this.args.model.penaltyType === "silence") {
      return "admin.user.silence_modal_title";
    }
  }

  get buttonLabel() {
    if (this.args.model.penaltyType === "suspend") {
      return "admin.user.suspend";
    } else if (this.args.model.penaltyType === "silence") {
      return "admin.user.silence";
    }
  }

  get penaltyHistory() {
    return I18n.messageFormat("admin.user.penalty_history_MF", {
      SUSPENDED: this.args.model.user.penalty_counts?.suspended,
      SILENCED: this.args.model.user.penalty_counts?.silenced,
    });
  }

  get canPenalize() {
    if (this.args.model.penaltyType === "suspend") {
      return this.args.model.user.canSuspend;
    } else if (this.args.model.penaltyType === "silence") {
      return this.args.model.user.canSilence;
    }
    return false;
  }

  get submitDisabled() {
    return (
      this.penalizing ||
      isEmpty(this.penalizeUntil) ||
      !this.reason ||
      (this.postAction === "delete_all" && !this.readyToDeleteAll)
    );
  }

  @action
  continueToClassification() {
    if (!this.submitDisabled) {
      this.classificationStep = true;
    }
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
  async penalizeUser(classification) {
    const dsaClassification = this.args.model.dsaClassification
      ? { ...classification }
      : undefined;
    if (this.submitDisabled) {
      return;
    }
    this.penalizing = true;
    this.confirmClose = true;

    let result;
    try {
      if (this.args.model.before && !this.#beforeCompleted) {
        await this.args.model.before();
        this.#beforeCompleted = true;
      }

      const opts = {
        reason: this.reason,
        message: this.message,
        post_id: this.args.model.postId,
        post_action: this.postAction,
        post_edit: this.postEdit,
        other_user_ids: this.otherUserIds,
        reviewable_id: this.args.model.reviewableId,
        ...(dsaClassification ? { dsa_classification: dsaClassification } : {}),
      };

      if (this.args.model.penaltyType === "suspend") {
        opts.suspend_until = this.penalizeUntil;
        result = await (this.args.model.perform
          ? this.args.model.perform(opts)
          : this.args.model.user.suspend(opts));
      } else if (this.args.model.penaltyType === "silence") {
        opts.silenced_till = this.penalizeUntil;
        result = await (this.args.model.perform
          ? this.args.model.perform(opts)
          : this.args.model.user.silence(opts));
      } else {
        // eslint-disable-next-line no-console
        console.error("Unknown penalty type:", this.args.model.penaltyType);
      }
      this.args.closeModal({ success: true });
      if (this.args.model.successCallback) {
        await this.args.model.successCallback({
          ...result,
          shouldDeleteAllPosts:
            this.postAction === "delete_all" && this.readyToDeleteAll,
        });
      }
    } catch (error) {
      this.flash = result ? extractError(result) : extractError(error);
    } finally {
      this.penalizing = false;
    }
  }

  @action
  async cancelPenalty() {
    if (await this.warnBeforeClosing()) {
      this.args.closeModal({ success: false });
    }
  }

  @action
  async warnBeforeClosing() {
    if (this.penalizing) {
      return false;
    }

    if (!this.confirmClose && (this.reason?.length || this.message?.length)) {
      return this.dialog.confirm({
        message: i18n("admin.user.confirm_cancel_penalty"),
      });
    }

    return true;
  }

  @action
  similarUsersChanged(userIds) {
    this.otherUserIds = userIds;
  }

  @action
  updateReadyToDeleteAll(flag) {
    this.readyToDeleteAll = flag;
  }

  <template>
    <DModal
      class="{{@model.penaltyType}}-user-modal --large"
      @beforeClose={{this.warnBeforeClosing}}
      @closeModal={{@closeModal}}
      @dismissable={{not this.penalizing}}
      @flash={{this.flash}}
      @title={{i18n this.modalTitle}}
    >
      <:body>
        {{#if this.canPenalize}}
          {{#if @model.dsaClassification}}
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
            <div class="penalty-duration-controls">
              {{#if (eq @model.penaltyType "suspend")}}
                <DFutureDateInput
                  class="suspend-until"
                  @clearable={{false}}
                  @input={{this.penalizeUntil}}
                  @label="admin.user.suspend_duration"
                  @onChangeInput={{fn (mut this.penalizeUntil)}}
                />
              {{else if (eq @model.penaltyType "silence")}}
                <DFutureDateInput
                  class="silence-until"
                  @clearable={{false}}
                  @input={{this.penalizeUntil}}
                  @label="admin.user.silence_duration"
                  @onChangeInput={{fn (mut this.penalizeUntil)}}
                />
              {{/if}}
            </div>
            {{#if (eq @model.penaltyType "suspend")}}
              <div class="penalty-reason-visibility">
                {{#if this.siteSettings.hide_suspension_reasons}}
                  {{trustHTML (i18n "admin.user.suspend_reason_hidden_label")}}
                {{else}}
                  {{trustHTML (i18n "admin.user.suspend_reason_label")}}
                {{/if}}
              </div>
            {{/if}}
            <AdminPenaltyReason
              @message={{this.message}}
              @onChangeMessage={{fn (mut this.message)}}
              @onChangeReason={{fn (mut this.reason)}}
              @penaltyType={{@model.penaltyType}}
            />
            {{#if @model.postId}}
              <AdminPenaltyPostAction
                @onChangePostAction={{fn (mut this.postAction)}}
                @onChangePostEdit={{fn (mut this.postEdit)}}
                @onDeleteAllPostsReady={{this.updateReadyToDeleteAll}}
                @postAction={{this.postAction}}
                @postEdit={{this.postEdit}}
                @user={{@model.user}}
              />
            {{/if}}
            {{#if @model.user.similar_users_count}}
              <AdminPenaltySimilarUsers
                @onUsersChanged={{this.similarUsersChanged}}
                @penaltyType={{@model.penaltyType}}
                @selectedUserIds={{this.otherUserIds}}
                @user={{@model.user}}
              />
            {{/if}}
          </div>
          {{#if @model.dsaClassification}}
            <div hidden={{not this.classificationStep}}>
              <DsaModerationDetails
                @formId="penalty-dsa-classification-form"
                @onSubmit={{this.penalizeUser}}
                @options={{@model.dsaClassification}}
              />
            </div>
          {{/if}}
        {{else}}
          {{#if (eq @model.penaltyType "suspend")}}
            <div class="cant-suspend">{{i18n "admin.user.cant_suspend"}}</div>
          {{else if (eq @model.penaltyType "silence")}}
            <div class="cant-silence">{{i18n "admin.user.cant_silence"}}</div>
          {{/if}}
        {{/if}}
        <div
          class="penalty-history"
          hidden={{this.classificationStep}}
        >{{trustHTML this.penaltyHistory}}</div>
      </:body>
      <:footer>
        {{#if (and @model.dsaClassification (not this.classificationStep))}}
          <DButton
            class="btn-primary"
            @action={{this.continueToClassification}}
            @disabled={{this.submitDisabled}}
            @label="continue"
          />
        {{else}}
          <DButton
            class="btn-danger perform-penalize"
            type={{if @model.dsaClassification "submit" "button"}}
            @action={{unless @model.dsaClassification this.penalizeUser}}
            @disabled={{this.submitDisabled}}
            @form={{if
              @model.dsaClassification
              "penalty-dsa-classification-form"
            }}
            @icon="ban"
            @isLoading={{this.penalizing}}
            @label={{this.buttonLabel}}
          />
          {{#if @model.dsaClassification}}
            <DButton
              class="btn-flat"
              @action={{this.backToAction}}
              @disabled={{this.penalizing}}
              @label="back_button"
            />
          {{/if}}
        {{/if}}
        {{#unless @model.dsaClassification}}
          <DButton
            class="btn-flat d-modal-cancel"
            @action={{this.cancelPenalty}}
            @disabled={{this.penalizing}}
            @label="cancel"
          />
        {{/unless}}
      </:footer>
    </DModal>
  </template>
}
