# frozen_string_literal: true

RSpec.describe "Classifying restrictive reviewable actions" do
  fab!(:admin)
  fab!(:topic, :topic_with_op)

  let(:review_page) { PageObjects::Pages::Review.new }
  let(:modal) { PageObjects::Modals::DsaModeration.new }
  let(:composer) { PageObjects::Components::Composer.new }
  let(:rule) { { ground: "Be respectful", explanation: "Personal attacks are not allowed." } }
  let(:category) { "Other violation of terms and conditions" }

  let(:note) do
    "Classified this moderation decision for DSA reporting. Community rule: #{rule[:ground]} Category: #{category}"
  end

  before do
    SiteSetting.dsa_reporting_enabled = true
    SiteSetting.dsa_community_rules = [rule].to_json
    sign_in(admin)
  end

  it "lets staff classify account deletion" do
    user = Fabricate(:user)
    flagger = Fabricate(:user, trust_level: TrustLevel[3])
    post = Fabricate(:post, topic:, user:)
    reviewable = PostActionCreator.spam(flagger, post).reviewable

    review_page.visit_reviewable(reviewable)
    review_page.select_bundled_action(reviewable, "post-delete_user_block", bundle_index: 1)

    expect(modal).to have_action_title("Delete and block user")
    expect(modal).to have_no_confirmation_prompt
    expect(modal).to have_classification

    modal.select_rule(rule[:ground])
    modal.select_category(category)
    modal.confirm("Delete and block user")

    expect(modal).to be_closed

    review_page.visit_reviewable(reviewable)

    expect(review_page).to have_note(note)
    expect(review_page).to have_reviewable_with_approved_status(reviewable)
  end

  it "lets staff reject a registration through the ordinary rejection dialog with DSA enabled" do
    SiteSetting.must_approve_users = true
    registration = Fabricate(:reviewable_user, target: Fabricate(:user, approved: false))
    rejection_modal = PageObjects::Modals::RejectReasonReviewable.new
    reason = "Membership is limited to employees."

    review_page.visit_reviewable(registration)
    review_page.select_bundled_action(registration, "user-delete_user_block")
    rejection_modal.fill_in_rejection_reason(reason)
    rejection_modal.select_send_rejection_email_checkbox
    rejection_modal.delete_user

    expect(review_page).to have_reviewable_with_rejected_status(registration)
    expect(review_page).to have_reviewable_with_rejection_reason(registration, reason)
  end

  it "lets staff classify before editing and leaves the review pending when the edit is discarded" do
    post = topic.first_post
    reviewable =
      Fabricate(:reviewable_flagged_post, target: post, target_created_by: post.user, topic:)

    review_page.visit_reviewable(reviewable)
    review_page.select_bundled_action(reviewable, "post-agree_and_edit", bundle_index: 1)

    expect(modal).to have_action_title("Edit post")

    modal.select_rule(rule[:ground])
    modal.select_category(category)
    modal.confirm("Continue to editor")

    expect(modal).to be_closed
    expect(composer).to be_opened

    composer.fill_content("A correction that should be discarded.")
    composer.discard
    discard_modal = PageObjects::Modals::DiscardDraft.new

    expect(discard_modal).to be_open

    discard_modal.click_discard

    expect(composer).to be_closed
    expect(review_page).to have_reviewable_with_pending_status(reviewable)
    expect(review_page).to have_no_note(note)

    review_page.select_bundled_action(reviewable, "post-agree_and_edit", bundle_index: 1)
    modal.select_rule(rule[:ground])
    modal.select_category(category)
    modal.confirm("Continue to editor")

    expect(composer).to be_opened

    composer.fill_content("A corrected contribution to the discussion.")
    composer.submit

    expect(composer).to be_closed
    expect(review_page).to have_reviewable_with_approved_status(reviewable)

    page.refresh

    expect(review_page).to have_note(note)
  end

  it "lets staff keep revision feedback while classifying the rejection" do
    queued = Fabricate(:reviewable_queued_post_topic)
    revision = PageObjects::Modals::ReviseAndRejectPost.new
    reason = "Personal attacks"
    feedback = "Please address the suggestion without insulting the author."

    review_page.visit_reviewable(queued)
    review_page.select_bundled_action(queued, "revise_and_reject_post")
    revision.fill_reason(reason)
    revision.fill_feedback(feedback)

    expect(modal).to have_no_cancel_button

    modal.continue

    expect(modal).to have_classification

    modal.select_rule(rule[:ground])
    modal.select_category(category)
    modal.back

    expect(revision).to have_reason(reason)
    expect(revision).to have_feedback(feedback)

    modal.continue

    expect(modal).to have_selected_category(category)

    revision.click_primary_button

    expect(modal).to be_closed
    expect(review_page).to have_reviewable_with_rejected_status(queued)

    page.refresh

    expect(review_page).to have_note(note)
  end
end
