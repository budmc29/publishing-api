module Services
  class CreateContentItem
    attr_reader :base_path, :payload, :user_facing_version, :lock_version, :state

    def initialize(payload:, lock_version:, content_store: "draft")
      @payload = payload.merge(content_store: content_store)
      @lock_version = lock_version
    end

    def create_content_item(save: true, &block)
      ContentItem.new(content_attributes).tap do |content_item|
        lock_version = LockVersion.new(target: content_item, number: lock_version)
        ensure_link_set_exists(content_item)
        puts "SOMETHING DISTINCTIVE!"
        yield(content_item) if block
        puts save
        content_item.save! if save
      end
    end

  private

    def content_attributes
      payload.slice(*ContentItem::TOP_LEVEL_FIELDS)
    end

    def locale
      payload.fetch(:locale, ContentItem::DEFAULT_LOCALE)
    end

    def ensure_link_set_exists(content_item)
      existing_link_set = LinkSet.find_by(content_id: content_item.content_id)
      return if existing_link_set

      link_set = LinkSet.create!(content_id: content_item.content_id)
      LockVersion.create!(target: link_set, number: 1)
    end
  end
end
