require "rails_helper"

RSpec.describe Guide do
  context "with a topic" do
    let(:guide) do
      create(:guide, slug: "/service-manual/topic-name/slug")
    end

    let!(:topic) do
      topic = create(:topic)
      topic_section = create(
        :topic_section,
        "title" => "Title",
        "description" => "Description",
        topic:,
      )
      topic_section.guides << guide
      topic
    end

    describe "#included_in_a_topic?" do
      it "returns true" do
        expect(guide).to be_included_in_a_topic
      end
    end

    describe "#topic" do
      it "returns the topic" do
        expect(guide.reload.topic).to eq topic
      end
    end
  end

  context "without a topic" do
    let(:guide) do
      Guide.new(slug: "/service-manual/topic-name/slug")
    end

    describe "#included_in_a_topic?" do
      it "returns false" do
        expect(guide).to_not be_included_in_a_topic
      end
    end

    describe "#topic" do
      it "returns nil" do
        expect(guide.topic).to be_nil
      end
    end
  end

  describe "on create callbacks" do
    it "generates and sets content_id on create" do
      topic_section = create(:topic_section)
      guide = Guide.new(slug: "/service-manual/topic-name/slug", content_id: nil)
      guide.topic_section_guides.build(topic_section:)
      guide.save!

      expect(guide.content_id).to be_present
    end
  end

  describe "validations" do
    describe "the slug" do
      it "is not valid when it does not include a topic" do
        guide = build(:guide, slug: "/service-manual/guide-path")

        expect(guide).not_to be_valid
        expect(guide.errors.full_messages_for(:slug)).to eq [
          "Slug must be present and start with '/service-manual/[topic]'",
        ]
      end

      it "is not valid when it includes non alphanumeric characters" do
        guide = build(:guide, slug: "/service-manual/topic-name/$")

        expect(guide).not_to be_valid
        expect(guide.errors.full_messages_for(:slug)).to eq [
          "Slug can only contain letters, numbers and dashes",
          "Slug must be present and start with '/service-manual/[topic]'",
        ]
      end

      it "is not valid when the topic path includes non alphanumeric characters" do
        guide = build(:guide, slug: "/service-manual/$$$/title")

        expect(guide).not_to be_valid
        expect(guide.errors.full_messages_for(:slug)).to eq [
          "Slug can only contain letters, numbers and dashes",
          "Slug must be present and start with '/service-manual/[topic]'",
        ]
      end

      it "is valid when it contains the topic and is alphanumeric" do
        guide = build(:guide, slug: "/service-manual/topic-name/guide-name")

        expect(guide).to be_valid
      end

      it "can be changed if the guide has never been published" do
        guide = create(:guide, :with_draft_edition)

        guide.slug = "/service-manual/topic-name/something-else"

        expect(guide).to be_valid
      end

      it "cannot be changed if the guide has been published" do
        guide = create(:guide, :with_published_edition)

        guide.slug = "/service-manual/topic-name/something-else"

        expect(guide).not_to be_valid
        expect(guide.errors.full_messages_for(:slug)).to eq [
          "Slug can't be changed as this guide has been published",
        ]
      end
    end

    describe "the content owner of the latest edition" do
      it "must be set" do
        edition_without_content_owner = build(:edition, content_owner: nil)
        guide = build(:guide, editions: [edition_without_content_owner])

        expect(guide).not_to be_valid
        expect(guide.errors.full_messages_for(:latest_edition)).to eq [
          "Latest edition must have a content owner",
        ]
      end
    end

    describe "the topic section" do
      it "can be changed to a section in a different topic if the guide has never been published" do
        original_topic_section = create(
          :topic_section,
          topic: create(:topic, path: "/service-manual/original-topic"),
        )
        different_topic_section = create(
          :topic_section,
          topic: create(:topic, path: "/service-manual/different-topic"),
        )

        guide = create(
          :guide,
          topic_section: original_topic_section,
        )
        guide.topic_section_guides[0].topic_section_id = different_topic_section.id
        guide.save!

        expect(guide).to be_valid
        expect(original_topic_section.reload.guides).not_to include guide
        expect(different_topic_section.reload.guides).to include guide
      end

      it "cannot be changed to a section in a different topic if the guide has been published" do
        original_topic_section = create(
          :topic_section,
          topic: create(:topic, path: "/service-manual/original-topic"),
        )
        different_topic_section = create(
          :topic_section,
          topic: create(:topic, path: "/service-manual/different-topic"),
        )

        guide = create(
          :guide,
          :with_published_edition,
          topic_section: original_topic_section,
        )

        guide.topic_section_guides[0].topic_section_id = different_topic_section.id
        expect(guide).not_to be_valid

        expect(guide.errors.full_messages_for(:topic_section)).to eq [
          "Topic section can't be changed to a different topic as this guide has been published",
        ]
      end

      it "can be changed to a different section in the same topic even if the guide has been published" do
        topic = create(:topic)
        guide = create(:guide, :with_published_edition, topic:)
        new_topic_section = create(:topic_section, topic:)

        guide.topic_section_guides[0].topic_section_id = new_topic_section.id

        expect(guide).to be_valid
      end
    end
  end

  describe "#search" do
    it "searches titles" do
      create(:guide, title: "Standups")
      create(:guide, title: "Unit Testing")

      results = Guide.search("testing").map(&:title)
      expect(results).to eq ["Unit Testing"]
    end

    it "does not return duplicates" do
      create(
        :guide,
        editions: [
          create(:edition, :draft, title: "dictionary"),
          create(:edition, :published, title: "thesaurus"),
        ],
      )

      expect(described_class.search("dictionary").count).to eq 0
      expect(described_class.search("thesaurus").count).to eq 1
    end

    it "searches slugs" do
      create(:guide, title: "Guide 1", slug: "/service-manual/topic-name/1")
      create(:guide, title: "Guide 2", slug: "/service-manual/topic-name/2")

      results = Guide.search("/service-manual/topic-name/2").map(&:title)
      expect(results).to eq ["Guide 2"]
    end
  end
end

RSpec.describe Guide, "#latest_edition_per_edition_group" do
  it "returns only the latest edition from editions that share the same edition number" do
    topic_section = create(:topic_section)
    guide = Guide.new(slug: "/service-manual/topic-name/slug")
    guide.editions << build(:edition, version: 1, created_at: 2.days.ago)
    first_version_second_edition = build(:edition, version: 1, created_at: 1.day.ago)
    guide.editions << first_version_second_edition
    guide.editions << build(:edition, version: 2, created_at: 2.days.ago)
    second_version_second_edition = build(:edition, version: 2, created_at: 1.day.ago)
    guide.editions << second_version_second_edition
    guide.topic_section_guides.build(topic_section:)
    guide.save!

    expect(
      guide.latest_edition_per_edition_group,
    ).to eq([second_version_second_edition, first_version_second_edition])
  end
end

RSpec.describe Guide, "#editions_since_last_published" do
  it "returns editions since last published" do
    guide = create(:guide, :with_published_edition)
    edition1 = build(:edition)
    edition2 = build(:edition)
    guide.editions << edition1
    guide.editions << edition2

    expect(guide.editions_since_last_published.to_a).to match_array [edition2, edition1]
  end
end

RSpec.describe Guide, "#has_been_published?" do
  it "returns true if the guide has been published" do
    guide = create(:guide, :with_published_edition)
    expect(guide.has_been_published?).to be true
  end

  it "returns false if the guide has been unpublished" do
    guide = create(:guide, :has_been_unpublished)
    expect(guide.has_been_published?).to be false
  end
end

RSpec.describe Guide, "#live_edition" do
  it "returns the most recently published edition" do
    guide = create(:guide, created_at: 5.days.ago)
    latest_published_edition = build(:edition, :published, created_at: 3.days.ago)
    guide.editions << latest_published_edition
    guide.editions << create(:edition, :published, created_at: 4.days.ago)

    expect(guide.live_edition).to eq(latest_published_edition)
  end

  it "returns the most recently published edition since unpublication" do
    guide = create(:guide, created_at: 5.days.ago)
    guide.editions << build(:edition, :published, created_at: 4.days.ago)
    guide.editions << build(:edition, :unpublished, created_at: 3.days.ago)
    latest_published_edition = build(:edition, :published, created_at: 2.days.ago)
    guide.editions << latest_published_edition

    expect(guide.live_edition).to eq(latest_published_edition)
  end

  it "returns nil if it has been unpublished since publication" do
    guide = create(:guide, created_at: 5.days.ago)
    guide.editions << create(:edition, :published, created_at: 4.days.ago)
    guide.editions << create(:edition, :unpublished, created_at: 3.days.ago)

    expect(guide.live_edition).to eq(nil)
  end

  it "is nil if an edition hasn't been published yet" do
    guide = create(:guide)

    expect(guide.live_edition).to eq(nil)
  end
end

RSpec.describe Guide, ".in_state" do
  it "returns guides that have a latest edition in a state" do
    published_guide = create(:guide, :with_published_edition)
    ready_guide = create(:guide, :with_ready_edition)
    draft_guide = create(:guide, :with_draft_edition)

    draft_guides = Guide.where(type: nil).in_state("draft")
    expect(draft_guides).to eq [draft_guide]

    ready_guides = Guide.where(type: nil).in_state("ready")
    expect(ready_guides).to eq [ready_guide]

    published_guides = Guide.where(type: nil).in_state("published")
    expect(published_guides).to eq [published_guide]
  end
end

RSpec.describe Guide, ".by_author" do
  it "returns guides that have a latest edition by the author" do
    expected_author = create(:user)
    another_author = create(:user)

    create(
      :guide,
      editions: [
        build(:edition, author: expected_author),
        build(:edition, author: another_author),
      ],
    )
    expected_guide = create(
      :guide,
      editions: [
        build(:edition, author: another_author),
        build(:edition, author: expected_author),
      ],
    )

    expect(Guide.where(type: nil).by_author(expected_author.id).to_a).to eq [
      expected_guide,
    ]
  end
end

RSpec.describe Guide, ".owned_by" do
  it "returns guides with a latest edition owned by the content owner" do
    expected_content_owner = create(:guide_community)
    another_content_owner = create(:guide_community)

    create(
      :guide,
      editions: [
        build(:edition, content_owner: expected_content_owner),
        build(:edition, content_owner: another_content_owner),
      ],
    )
    expected_guide = create(
      :guide,
      editions: [
        build(:edition, content_owner: another_content_owner),
        build(:edition, content_owner: expected_content_owner),
      ],
    )

    expect(Guide.where(type: nil).owned_by(expected_content_owner.id).to_a).to eq [
      expected_guide,
    ]
  end
end

RSpec.describe Guide, ".by_type" do
  it "returns guides with a specific type" do
    guide_community_edition = build(:edition, content_owner: nil, title: "Agile Community")
    guide_community = create(:guide_community, editions: [guide_community_edition])

    edition = build(:edition, content_owner: guide_community, title: "Scrum")
    create(:guide, editions: [edition])

    expect(described_class.by_type("GuideCommunity")).to eq([guide_community])
  end

  it "returns guides of type Guide if nil or empty string is supplied" do
    guide_community_edition = build(:edition, content_owner: nil, title: "Agile Community")
    guide_community = create(:guide_community, editions: [guide_community_edition])

    edition = build(:edition, content_owner: guide_community, title: "Scrum")
    guide = create(:guide, editions: [edition])

    expect(described_class.by_type(nil)).to eq([guide])
    expect(described_class.by_type("")).to eq([guide])
  end
end

RSpec.describe Guide, ".live" do
  it "returns guides that are currently published" do
    create(:guide, :with_draft_edition)
    create(:guide, :with_review_requested_edition)
    create(:guide, :with_ready_edition)
    with_published_edition_guide = create(:guide, :with_published_edition)
    with_previously_published_edition_guide = create(:guide, :with_previously_published_edition)
    create(:guide, :has_been_unpublished)

    expect(Guide.live).to match_array([with_published_edition_guide, with_previously_published_edition_guide])
  end
end

RSpec.describe Guide, ".not_unpublished" do
  it "returns guides that are currently published" do
    guide_community = create(:guide_community)

    relevant_traits = %i[
      with_draft_edition
      with_review_requested_edition
      with_ready_edition
      with_published_edition
      with_previously_published_edition
    ]

    relevant_guides = relevant_traits.map do |trait|
      create(:guide, trait, edition: { content_owner_id: guide_community.id })
    end

    create(:guide, :has_been_unpublished, edition: { content_owner_id: guide_community.id })

    expect(Guide.not_unpublished).to match_array(relevant_guides + [guide_community])
  end
end

RSpec.describe Guide, ".destroy" do
  it "destroys any associated editions" do
    guide = create(:guide, :with_draft_edition)
    guide.destroy!

    expect(Edition.where(guide_id: guide.id).count).to eq 0
  end

  it "destroys any associations with topic sections" do
    guide = create(:guide)
    guide.destroy!

    expect(TopicSectionGuide.where(guide_id: guide.id).count).to eq 0
  end
end
