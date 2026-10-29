# frozen_string_literal: true

describe "Classifying reviewable moderation" do
  fab!(:admin)
  fab!(:topic, :topic_with_op)

  let(:review_page) { PageObjects::Pages::Review.new }
  let(:modal) { PageObjects::Modals::DsaModeration.new }
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

  it "lets staff classify a hidden post and close the form without handling the review" do
    post = Fabricate(:post, topic: topic)
    reviewable =
      Fabricate(:reviewable_flagged_post, target: post, target_created_by: post.user, topic: topic)

    review_page.visit_reviewable(reviewable)
    review_page.select_bundled_action(reviewable, "post-agree_and_hide", bundle_index: 1)

    expect(modal).to have_action_title("Hide post")
    expect(modal).to have_classification
    expect(modal).to have_no_cancel_button

    modal.close

    expect(modal).to be_closed
    expect(review_page).to have_reviewable_with_pending_status(reviewable)

    review_page.select_bundled_action(reviewable, "post-agree_and_hide", bundle_index: 1)
    modal.confirm("Hide post")

    expect(modal).to have_required_errors

    modal.select_rule(rule[:ground])
    modal.select_category(category)
    modal.confirm("Hide post")

    expect(modal).to be_closed
    expect(review_page).to have_reviewable_with_approved_status(reviewable)
    expect(review_page).to have_note(note)

    page.refresh

    expect(review_page).to have_note(note)
  end

  it "lets staff keep suspension details and classification when going back" do
    post = Fabricate(:post, topic: topic)
    reviewable =
      Fabricate(:reviewable_flagged_post, target: post, target_created_by: post.user, topic: topic)
    penalty_modal = PageObjects::Modals::PenalizeUser.new("suspend")

    review_page.visit_reviewable(reviewable)
    review_page.select_bundled_action(reviewable, "post-agree_and_suspend", bundle_index: 1)

    expect(modal).to have_action_title("Suspend user")
    expect(modal).to have_content("@#{post.user.username}")
    expect(modal).to have_no_cancel_button

    penalty_modal.set_future_date("two_weeks")

    expect(modal).to have_disabled_continue

    penalty_modal.fill_in_suspend_reason("Repeated personal attacks.")
    modal.continue

    expect(modal).to have_action_title("Suspend user")
    expect(modal).to have_classification
    expect(modal).to have_focused_step("DSA classification")
    expect(modal).to have_no_cancel_button

    modal.select_rule(rule[:ground])
    modal.select_category(category)
    modal.close
    dialog = PageObjects::Components::Dialog.new

    expect(dialog).to be_open

    dialog.click_no

    expect(modal).to have_selected_category(category)

    modal.back

    expect(modal).to have_focused_step("Action details")
    expect(modal).to have_action_title("Suspend user")
    expect(penalty_modal).to have_suspend_reason("Repeated personal attacks.")

    modal.continue

    expect(modal).to have_selected_category(category)

    modal.confirm("Suspend user")

    expect(modal).to be_closed
    expect(review_page).to have_reviewable_with_approved_status(reviewable)

    page.refresh

    expect(review_page).to have_note(note)

    admin_user_page = PageObjects::Pages::AdminUser.new
    admin_user_page.visit(post.user)

    expect(admin_user_page).to have_suspension_reason("Repeated personal attacks.")
  end

  it "lets staff classify a post after loading another page of reviews" do
    post = Fabricate(:post, topic: topic)
    reviewable =
      Fabricate(:reviewable_flagged_post, target: post, target_created_by: post.user, topic: topic)
    newer_reviewable = Fabricate(:reviewable_flagged_post)

    stub_const(ReviewablesController, "PER_PAGE", 1) do
      visit("/review?sort_order=created_at")

      expect(review_page).to have_reviewable_with_pending_status(newer_reviewable)

      page.scroll_to(:bottom)

      expect(review_page).to have_reviewable_with_pending_status(reviewable)

      review_page.select_bundled_action(reviewable, "post-agree_and_hide", bundle_index: 1)

      expect(modal).to have_action_title("Hide post")

      modal.select_rule(rule[:ground])
      modal.select_category(category)
      modal.confirm("Hide post")

      expect(modal).to be_closed
      expect(review_page).to have_reviewable_with_approved_status(reviewable)
    end

    review_page.visit_reviewable(reviewable)

    expect(review_page).to have_note(note)
  end
end
