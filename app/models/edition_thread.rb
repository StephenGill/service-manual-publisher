class EditionThread
  def initialize(most_recent_edition)
    @most_recent_edition = most_recent_edition
  end

  def events
    @events = []
    @events << NewDraftEvent.new(all_editions_in_thread.first)
    @events << AssignedToEvent.new(all_editions_in_thread.first)

    current_state = all_editions_in_thread.first.state

    all_editions_in_thread.each do |edition|
      if edition.state != current_state
        @events << StateChangeEvent.new(edition)
      end

      edition.comments.each do |comment|
        @events << CommentEvent.new(comment)
      end
    end
    @events
  end

private

  def all_editions_in_thread
    @_all_editions_in_thread =
      Edition.where(guide_id: @most_recent_edition.guide_id, version: @most_recent_edition.version)
             .order('created_at')
  end

  NewDraftEvent = Struct.new(:edition)
  AssignedToEvent = Struct.new(:edition)
  CommentEvent = Struct.new(:comment)
  StateChangeEvent = Struct.new(:edition) do
    def action
      case edition.state
      when "review_requested"
        "Review requested"
      else
        raise NotImplementedError
      end
    end
  end
end
