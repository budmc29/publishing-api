class LinkExpansion::ContentCache
  def initialize(with_drafts:, locale:, preload_editions: [], preload_content_ids: [])
    @with_drafts = with_drafts
    @locale = locale
    @store = build_store(preload_editions, preload_content_ids)
  end

  def find(content_id, preloaded = false)
    if store.has_key?(content_id)
      store[content_id]
    else
      puts "#{content_id} not in cache" if preloaded
      store[content_id] = edition(content_id)
    end
  end

private

  attr_reader :store, :with_drafts, :locale

  def build_store(editions, content_ids)
    start = Time.now
    store = Hash[editions.map { |edition| [edition.content_id, edition] }]

    to_preload = content_ids - editions.map(&:content_id)
    built_store = editions(to_preload).each_with_object(store) do |edition, hash|
      hash[edition.content_id] = edition
    end
    puts "ContentCache#build_store took #{(Time.now - start)} seconds"
    built_store
  end

  def edition(content_id)
    editions([content_id]).first
  end

  def locale_fallback_order
    [locale, Edition::DEFAULT_LOCALE].uniq
  end

  def editions(content_ids)
    return [] unless content_ids.present?
    edition_ids = Queries::GetEditionIdsWithFallbacks.(content_ids,
      locale_fallback_order: locale_fallback_order,
      state_fallback_order: state_fallback_order,
    )
    Edition.with_document.includes(:document).where(id: edition_ids).all
  end

  def state_fallback_order
    with_drafts ? %i[draft published withdrawn] : %i[published withdrawn]
  end
end
