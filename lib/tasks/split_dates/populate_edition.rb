class Tasks::SplitDates::PopulateEdition
  def initialize(edition)
    @edition = edition
  end

  def call
    populate_first_published_at
    populate_published_at
    populate_major_published_at
    populate_last_edited_at
  end

private

  attr_reader :edition
  delegate :document, to: :edition

  def populate_first_published_at
    return if has_new_first_published_dates? || !document_has_been_published?
    edition.temporary_first_published_at = FirstPublishedAtResolver.new(
      edition, can_use_events?
    ).call

    if !within_1_sec(edition.first_published_at, edition.temporary_first_published_at)
      edition.publisher_first_published_at = edition.first_published_at
    end
  end

  def populate_published_at
    return if has_published_dates? || edition.draft?
    edition.published_at = PublishedAtResolver.new(
      edition, can_use_events?
    ).call
  end

  def populate_major_published_at
    return if has_major_published_dates? || !document_has_been_published?
    edition.major_published_at = MajorPublishedAtResolver.new(edition).call

    if !within_1_sec(edition.public_updated_at, edition.major_published_at)
      edition.publisher_major_published_at = edition.public_updated_at
    end
  end

  def populate_last_edited_at
    return if has_last_edited_dates?
    edition.temporary_last_edited_at = LastEditedAtResolver.new(
      edition, can_use_events?
    ).call

    if !within_1_sec(edition.last_edited_at, edition.temporary_last_edited_at)
      edition.publisher_last_edited_at = edition.last_edited_at
    end
  end

  def document_has_been_published?
    !(edition.state == "draft" && edition.user_facing_version == 1)
  end

  def has_new_first_published_dates?
    edition.temporary_first_published_at || edition.publisher_first_published_at
  end

  def has_major_published_dates?
    edition.major_published_at || edition.publisher_major_published_at
  end

  def has_published_dates?
    edition.published_at || edition.publisher_published_at
  end

  def has_last_edited_dates?
    edition.temporary_last_edited_at || edition.publisher_last_edited_at
  end

  def can_use_events?
    @can_use_events ||= Document.where(content_id: document.content_id).count == 1
  end

  def within_1_sec(date_a, date_b)
    diff = (date_b.to_f * 1000).to_i - (date_a.to_f * 1000).to_i
    diff.abs > 1000
  end

  class FirstPublishedAtResolver
    def initialize(edition, can_use_events)
      @edition = edition
      @can_use_events = can_use_events
    end

    def call
      resolve_from_action ||
        resolve_from_events ||
        resolve_from_previous_edition ||
        resolve_from_edition
    end

  private

    attr_reader :edition, :can_use_events
    delegate :document, to: :edition

    def resolve_from_action
      edition_id = document.editions.where(user_facing_version: 1).pluck(:id).first
      return unless edition_id
      Action.where(edition_id: edition_id, action: "Publish").pluck(:created_at).first
    end

    def resolve_from_events
      return unless can_use_events
      Event.where(
        content_id: document.content_id,
        action: "Publish"
      ).order(id: :asc).limit(1).pluck(:created_at).first
    end

    def resolve_from_previous_edition
      document.editions
        .where("user_facing_version < ?", edition.user_facing_version)
        .where.not(temporary_first_published_at: nil)
        .order(user_facing_version: :asc)
        .limit(1)
        .pluck(:temporary_first_published_at)
        .first
    end

    def resolve_from_edition
      return unless edition.first_published_at
      # If nano seconds on time aren't 0 we assume we set this date
      edition.first_published_at.nsec != 0 ? edition.first_published_at : nil
    end
  end

  class PublishedAtResolver
    def initialize(edition, can_use_events)
      @edition = edition
      @can_use_events = can_use_events
    end

    def call
      resolve_from_action || resolve_from_events
    end

  private

    attr_reader :edition, :can_use_events, :next_edition
    delegate :document, to: :edition

    def resolve_from_action
      Action.where(edition_id: edition.id, action: "Publish").pluck(:created_at).first
    end

    def resolve_from_events
      return unless can_use_events
      scope = Event.where(
        content_id: document.content_id,
        action: %w(Publish Unpublish),
      ).where("created_at > ?", edition.created_at)

      if next_edition
        scope = scope.where("created_at < ?", next_edition.created_at)
      end

      scope.order(created_at: :asc).pluck(:created_at).first
    end

    def next_edition
      scope = Edition
        .where(document_id: document.id)
        .where("user_facing_version > ?", edition.user_facing_version)
        .order(user_facing_version: :asc)
        .limit(1)
      @has_next ||= scope.exists?
      @next_edition ||= scope.first if @has_next
    end
  end

  class MajorPublishedAtResolver
    def initialize(edition)
      @edition = edition
    end

    def call
      # We're making an assumption here that an update_type of major means it
      # was actually published as that, this seems pretty safe since it'd be
      # very unlikely and confusing were update_type on model and the one used
      # in publish differed
      if edition.update_type == "major"
        edition.published_at || resolve_from_edition
      else
        previous_major_published&.published_at || resolve_from_edition
      end
    end

  private

    attr_reader :edition
    delegate :document, to: :edition

    def previous_major_published
      document.editions
        .where("user_facing_version < ?", edition.user_facing_version)
        .where(update_type: "major")
        .order(user_facing_version: :desc)
        .first
    end

    def resolve_from_edition
      return unless edition.public_updated_at
      # If nano seconds on time aren't 0 we assume we set this date
      edition.public_updated_at.nsec != 0 ? edition.public_updated_at : nil
    end
  end

  class LastEditedAtResolver
    def initialize(edition, can_use_events)
      @edition = edition
      @can_use_events = can_use_events
    end

    def call
      resolve_from_action || resolve_from_events || resolve_from_edition
    end

  private

    attr_reader :edition, :can_use_events
    delegate :document, to: :edition

    def resolve_from_action
      Action.where(edition_id: edition.id, action: "PutContent")
        .pluck(:created_at)
        .last
    end

    def resolve_from_events
      return unless can_use_events
      scope = Event.where(
        content_id: document.content_id,
        action: %w(PutContent PutContentWithLinks PutDraftContentWithLinks),
      ).where("created_at > ?", edition.created_at)

      if next_edition
        scope = scope.where("created_at < ?", next_edition.created_at)
      end

      scope.order(created_at: :asc).pluck(:created_at).first
    end

    def resolve_from_edition
      return unless edition.last_edited_at
      # If nano seconds on time aren't 0 we assume we set this date
      edition.last_edited_at.nsec != 0 ? edition.last_edited_at : nil
    end

    def next_edition
      scope = Edition
        .where(document_id: document.id)
        .where("user_facing_version > ?", edition.user_facing_version)
        .order(user_facing_version: :asc)
        .limit(1)
      @has_next ||= scope.exists?
      @next_edition ||= scope.first if @has_next
    end
  end
end
