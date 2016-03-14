require 'rails_helper'

RSpec.describe Edition, type: :model do
  describe "#notification_subscribers" do
    let(:joe) { build_stubbed(:user, name: "Joe") }
    let(:liz) { build_stubbed(:user, name: "Liz") }

    it "is the edition author and the current edition author" do
      edition = build(:edition, user: joe)
      current_edition = build(:edition, user: liz)
      guide = build(:guide, editions: [edition])
      guide.latest_edition = current_edition

      expect(edition.notification_subscribers).to match_array [joe, liz]
    end

    it "avoids duplicates" do
      first = build(:edition, user: joe)
      second = build(:edition, user: joe)
      guide = build(
        :guide,
        editions: [first],
        latest_edition: second,
      )

      expect(guide.latest_edition.notification_subscribers).to match_array [joe]
    end
  end

  describe "#phase" do
    it "defaults to 'beta'" do
      expect(Edition.new.phase).to eq 'beta'
    end
  end

  describe "#previously_published_edition" do
    let :editions do
      1.upto(4).map { build(:published_edition) }
    end

    before do
      create(:published_guide, editions: editions)
    end

    it "returns an edition that was the latest edition published before the current one" do
      expect(editions[2].previously_published_edition).to eq editions[1]
      expect(editions[3].previously_published_edition).to eq editions[2]
    end

    it "returns nil if it has no prviously published editions" do
      expect(editions[0].previously_published_edition).to eq nil
    end
  end

  describe "validations" do
    it "requires user to be present" do
      edition = build(:edition, user: nil)
      expect(edition).to be_invalid
      expect(edition.errors.full_messages_for(:user).size).to eq 1
    end

    it "does not allow updating already published editions" do
      edition = create(:published_edition)
      edition.update_attributes(title: "Republishing")
      expect(edition.errors.full_messages_for(:base).size).to eq 1
    end

    describe "state" do
      it "allows 'published' state" do
        edition = build(:published_edition)
        edition.valid?
        expect(edition.errors.full_messages_for(:state).size).to eq 0
      end

      valid_states = %w(draft review_requested approved)
      valid_states.each do |valid_state|
        it "allows '#{valid_state}' state" do
          edition = build(:edition, state: valid_state)
          edition.valid?
          expect(edition.errors.full_messages_for(:state).size).to eq 0
        end
      end

      it "does not allow arbitrary values" do
        edition = build(:edition, state: "invalid state")
        edition.valid?
        expect(edition.errors.full_messages_for(:state).size).to eq 1
      end

      it "does not allow empty change_note when the update_type is 'major'" do
        edition = build(:edition, update_type: "major", change_note: "")
        edition.valid?
        expect(edition.errors.full_messages_for(:change_note)).to eq ["Change note can't be blank"]
      end

      it "allows empty change_note when the update_type is 'minor'" do
        edition = build(:edition, update_type: "minor", change_note: "")
        edition.valid?
        expect(edition.errors.full_messages_for(:change_note).size).to eq 0
      end
    end

    context "an edition with broken links" do
      let :edition do
        build(
          :edition,
          body: "[broken link](http://not-a-real-domain-name.nope)",
        )
      end

      before do
        url_checker_double = double(:url_checker)
        allow(GovspeakUrlChecker).to receive(:new)
          .and_return(url_checker_double)
        allow(url_checker_double).to receive(:find_broken_urls)
          .and_return(["http://not-a-real-domain-name.nope"])
      end

      context "that is being published" do
        before do
          edition.state = "published"
        end

        it "validates links" do
          edition.valid?
          expect(edition.errors.full_messages_for(:body).size).to eq 1
        end
      end

      context "that is not being published" do
        it "does not validate links" do
          edition.valid?
          expect(edition.errors.full_messages_for(:body).size).to eq 0
        end
      end

    end
  end

  context "review and approval" do
    let :edition do
      edition = build(:edition)
      allow(edition).to receive(:persisted?) { true }
      edition
    end

    let :guide do
      build(:guide, slug: "/service-manual/topic-name/something", latest_edition: edition)
    end

    describe "#can_be_approved?" do
      let :user do
        build(:user)
      end

      it "returns true when a review has been requested" do
        edition.state = "review_requested"
        edition.save!
        expect(edition.can_be_approved?(user)).to be true
      end

      it "returns false when the user is also the editor" do
        edition.state = "review_requested"
        edition.user = build(:user, name: "anotehr", email: "email@address.org")
        expect(edition.can_be_approved?(edition.user)).to eq false
      end

      it "returns true when the user is also the editor but the ALLOW_SELF_APPROVAL flag is set" do
        edition.state = "review_requested"
        edition.user = build(:user, name: "anotehr", email: "email@address.org")
        edition.save!
        ENV['ALLOW_SELF_APPROVAL'] = '1'
        expect(edition.can_be_approved?(edition.user)).to eq true
        ENV.delete('ALLOW_SELF_APPROVAL')
      end

      it "returns false when latest_edition has not been saved" do
        allow(edition).to receive(:persisted?) { false }
        expect(edition.can_be_approved?(user)).to be false
      end
    end

    describe "#can_request_review?" do
      it "returns true when a review can be requested" do
        expect(edition.can_request_review?).to be true
      end

      it "returns false when latest_edition has not been saved" do
        allow(edition).to receive(:persisted?) { false }
        expect(edition.can_request_review?).to be false
      end

      it "returns false when a review has been requested" do
        edition.state = "review_requested"
        expect(edition.can_request_review?).to be false
      end

      it "returns false when a review has been published" do
        edition.state = "published"
        expect(edition.can_request_review?).to be false
      end

      it "returns false when a review has been approved" do
        edition.state = "approved"
        expect(edition.can_request_review?).to be false
      end
    end

    describe "#can_be_published?" do
      before do
        guide.save!
      end

      it "returns false if it's already published" do
        edition.state = "published"
        expect(edition.can_be_published?).to be false
      end

      it "returns false if it's not approved" do
        edition.state = "review_requested"
        expect(edition.can_be_published?).to be false
      end

      it "returns false if it's not the latest edition of a guide" do
        edition.state = "approved"
        guide.editions << edition.dup

        edition.guide.reload
        expect(edition.can_be_published?).to be false
      end

      it "returns true if it's the latest edition and is approved" do
        edition.state = "approved"
        expect(edition.can_be_published?).to be true
      end
    end
  end

  describe "#change_note_html" do
    it "renders markdown" do
      edition = build(:edition, change_note: "# heading")
      expect(edition.change_note_html).to eq "<h1>heading</h1>\n"
    end

    it "auto links" do
      edition = build(:edition, change_note: "http://example.org")
      expect(edition.change_note_html).to eq "<p><a href=\"http://example.org\">http://example.org</a></p>\n"
    end
  end

  describe "#draft_copy" do
    it "builds a new draft object with all fields but change notes" do
      edition = build(:published_edition, title: "Original Title", change_note: "Changes")
      draft = edition.draft_copy

      expect(draft.title).to eq "Original Title"
      expect(draft).to be_new_record
      expect(draft).to be_a_draft
      expect(draft.change_note).to be_blank
    end
  end
end
